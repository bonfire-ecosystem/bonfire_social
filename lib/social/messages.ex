defmodule Bonfire.Social.Messages do

  alias Bonfire.Data.Social.{Message, PostContent, Replied, Activity}
  alias Bonfire.Social.{Activities, FeedActivities}
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Common.Utils
  alias Ecto.Changeset
  import Bonfire.Boundaries.Queries
  alias Bonfire.Social.Threads
  alias Bonfire.Social.PostContents

  use Bonfire.Repo.Query,
      schema: Message,
      searchable_fields: [:id],
      sortable_fields: [:id]

  def draft(creator, attrs) do
    # TODO: create as private
    with {:ok, message} <- create(creator, attrs) do
      {:ok, message}
    end
  end

  def send(%{id: _} = creator, attrs) do
    #IO.inspect(attrs)

    cc = Utils.e(attrs, :circles, [])
    # cc = cc ++ (Bonfire.Tag.Tags.tag_ids(mentions) || []) # to make visible & notify for mentioned characters (should be configurable)

    repo().transact_with(fn ->
      with  {text, mentions, hashtags} <- Bonfire.Tag.TextContent.Process.process(creator, attrs),
            {:ok, message} <- create(creator, attrs, text),
            {:ok, post} <- Bonfire.Social.Tags.maybe_tag(creator, message, mentions),
            {:ok, activity} <- FeedActivities.maybe_notify(creator, :create, post, cc) do

              Bonfire.Me.Users.Boundaries.maybe_make_visible_for(creator, message, cc)

              #IO.inspect(message)
              Threads.maybe_push_thread(creator, activity, message)

              {:ok, %{message: message, activity: activity}}
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

  def read(message_id, %{id: _} = current_user) when is_binary(message_id) do

    with {:ok, message} <- build_query(id: message_id)
      |> Activities.object_preload_create_activity(current_user, [:default, :with_parents])
      |> Activities.as_permitted_for(current_user)
      # |> IO.inspect
      |> repo().single() do

        Utils.pubsub_subscribe(Utils.e(message, :activity, :replied, :thread_id, nil) || message.id) # subscribe to realtime feed updates

        {:ok, message} #|> repo().maybe_preload(controlled: [acl: [grants: [access: [:interacts]]]]) |> IO.inspect
      end
  end

  @doc "List posts created by the user and which are in their outbox, which are not replies"
  def list(%{id: current_user_id} = current_user, with_user \\ nil, cursor_before \\ nil, preloads \\ :all) when is_binary(with_user) or is_list(with_user) do

    # query FeedPublish

    q = if with_user && Utils.ulid(with_user) != current_user_id, do: FeedActivities.build_query(messages_with: Utils.ulid(with_user), distinct: :threads),
    else: FeedActivities.build_query(messages_for: current_user_id, distinct: :threads)

    q
    |> FeedActivities.feed_query_paginated(current_user, cursor_before, preloads)
  end


end
