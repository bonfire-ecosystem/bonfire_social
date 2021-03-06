defmodule Bonfire.Social.Messages do

  alias Bonfire.Data.Social.{Message, PostContent, Replied}
  alias Bonfire.Social.{Activities, FeedActivities}
  # alias Bonfire.Boundaries.Verbs
  alias Bonfire.Common.Utils
  alias Ecto.Changeset
  # import Bonfire.Boundaries.Queries
  alias Bonfire.Social.Threads
  alias Bonfire.Social.PostContents
  alias Bonfire.Boundaries.Verbs

  use Bonfire.Repo.Query,
      schema: Message,
      searchable_fields: [:id],
      sortable_fields: [:id]

  # def queries_module, do: Message
  def context_module, do: Message

  def draft(creator, attrs) do
    # TODO: create as private
    with {:ok, message} <- create(creator, attrs) do
      {:ok, message}
    end
  end

  def send(%{id: _} = creator, attrs) do
    #IO.inspect(attrs)

    repo().transact_with(fn ->
      with circles <- Utils.e(attrs, :circles, []),
        {text, mentions, _hashtags} <- Bonfire.Tag.TextContent.Process.process(creator, attrs),
        {:ok, message} <- create(creator, attrs, text),
        {:ok, tagged} <- Bonfire.Social.Tags.maybe_tag(creator, message, circles ++ mentions),
        {:ok, _} <- Bonfire.Me.Users.Boundaries.maybe_make_visible_for(creator, message, circles) do
         # TODO: optionally make visible to & notify mentioned characters (should be configurable)

          # IO.inspect(circles: circles)
          # IO.inspect(mentions: mentions)

          with {:ok, activity} <- FeedActivities.notify_characters(creator, :create, message, circles) do

            {:ok, Activities.activity_under_object(activity)}

          else e ->
            IO.inspect(could_not_notify: e)

            {:ok, message}
          end
      end
    end)
  end


  defp create(%{id: creator_id}, attrs, text \\ nil) do
    attrs = attrs
      |> Map.put(:post_content, PostContents.prepare_content(attrs, text))
      |> Map.put(:created, %{creator_id: creator_id})
      |> Map.put(:replied, Threads.maybe_reply(attrs))
      # |> IO.inspect

    repo().put(changeset(:create, attrs))
  end


  defp changeset(:create, attrs) do
    Message.changeset(%Message{}, attrs)
    |> Changeset.cast_assoc(:post_content, [:required, with: &PostContent.changeset/2])
    |> Changeset.cast_assoc(:created)
    |> Changeset.cast_assoc(:replied, [:required, with: &Replied.changeset/2])
  end

  def read(message_id, socket_or_current_user) when is_binary(message_id) do

    current_user = Utils.current_user(socket_or_current_user)

    with {:ok, message} <- Message |> EctoShorts.filter(id: message_id)
      |> Activities.read(socket_or_current_user) do

        {:ok, message}
      end
  end

  @doc "List posts created by the user and which are in their outbox, which are not replies"
  def list(current_user, with_user \\ nil, cursor_after \\ nil, preloads \\ :all)

  def list(%{id: current_user_id} = current_user, with_user, cursor_after, preloads) when ( is_binary(with_user) or is_list(with_user) or is_map(with_user) ) and with_user != current_user_id and with_user != current_user do
    # all messages between two people

    with_user_id = Utils.ulid(with_user)

    if with_user_id && with_user_id != current_user_id, do: [
      messages_involving: {{with_user_id, current_user_id}, &filter/3},
      # distinct: {:threads, &Bonfire.Social.Threads.filter/3}
    ]
    # |> IO.inspect(label: "list message filters")
    |> list_paginated(current_user, cursor_after, preloads),
    else: list(current_user, nil, cursor_after, preloads)

  end

  def list(%{id: current_user_id} = current_user, _, cursor_after, preloads) do
    # all current_user's message

    [
      messages_involving: {current_user_id, &filter/3},
      # distinct: {:threads, &Bonfire.Social.Threads.filter/3}
    ]
    # |> IO.inspect(label: "my messages filters")
    |> list_paginated(current_user, cursor_after, preloads)
  end

  def list(_current_user, _with_user, _cursor_before, _preloads), do: []

  def list_paginated(filters, current_user \\ nil, cursor_after \\ nil, preloads \\ :all, query \\ Message) do

    query
      # add assocs needed in timelines/feeds
      # |> join_preload([:activity])
      # |> IO.inspect(label: "pre-preloads")
      |> Activities.activity_preloads(current_user, preloads)
      |> EctoShorts.filter(filters)
      # |> IO.inspect(label: "message_paginated_post-preloads")
      |> Activities.as_permitted_for(current_user)
      # |> distinct([fp], [desc: fp.id, desc: fp.activity_id]) # not sure if/why needed... but possible fix for found duplicate ID for component Bonfire.UI.Social.ActivityLive in UI
      # |> order_by([fp], desc: fp.id)
      # |> IO.inspect(label: "post-permissions")
      # |> repo().many() # return all items
      |> Bonfire.Repo.many_paginated(before: cursor_after) # return a page of items (reverse chronological) + pagination metadata
      # |> IO.inspect(label: "feed")
  end

    #doc "List messages "
  def filter(:messages_involving, {user_id, current_user_id}, query) when is_binary(user_id) and is_binary(current_user_id) do
    verb_id = Verbs.verbs()[:create]

    query
    |> join_preload([:activity, :object_message])
    |> join_preload([:activity, :object_created])
    |> join_preload([:activity, :replied])
    |> join_preload([:activity, :tags])
    |> where(
      [activity: activity, object_message: message, object_created: created, replied: replied, tags: tags],
      not is_nil(message.id)
      and activity.verb_id==^verb_id
      and (
        (
          created.creator_id == ^current_user_id
          and tags.id == ^user_id
        ) or (
          created.creator_id == ^user_id
          # and tags.id == ^current_user_id
        )
      )
    )
  end

  def filter(:messages_involving, _user_id, query) do # replies on boundaries to filter which messages to show
    verb_id = Verbs.verbs()[:create]

    query
    |> join_preload([:activity, :object_message])
    |> join_preload([:activity, :object_created])
    |> join_preload([:activity, :replied])
    |> where(
      [activity: activity, object_message: message, object_created: created, replied: replied],
      not is_nil(message.id) # and activity.verb_id==^verb_id
    )
  end

end
