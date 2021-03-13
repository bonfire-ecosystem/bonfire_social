defmodule Bonfire.Social.FeedActivities do

  alias Bonfire.Data.Social.{Feed, FeedPublish, Like, Boost}
  alias Bonfire.Data.Identity.{User}
  alias Bonfire.Social.Feeds
  alias Bonfire.Social.Activities
  alias Bonfire.Common.Utils

  use Bonfire.Repo.Query,
      schema: FeedPublish,
      searchable_fields: [:id, :feed_id, :object_id],
      sortable_fields: [:id]

  def my_feed(user, cursor_after \\ nil) do

    # feeds the user is following
    feed_ids = Feeds.my_feed_ids(user)
    # IO.inspect(inbox_feed_ids: feed_ids)

    feed(feed_ids, user, cursor_after)
  end

  def feed(%{id: feed_id}, current_user \\ nil, cursor_after \\ nil), do: feed(feed_id, current_user, cursor_after)

  def feed(feed_id_or_ids, current_user, cursor_after) when is_binary(feed_id_or_ids) or is_list(feed_id_or_ids) do

    Utils.pubsub_subscribe(feed_id_or_ids) # subscribe to realtime feed updates

    build_query(feed_id: feed_id_or_ids) # query FeedPublish + assocs needed in timelines/feeds
      |> preload_join(:activity)
      |> Activities.activity_preloads(current_user, :all)
      |> Bonfire.Repo.many_paginated(before: cursor_after) # return a page of items + pagination metadata
      # |> IO.inspect
  end

  def feed(_, _, _), do: []

  # def feed(%{feed_publishes: _} = feed_for, _) do
  #   repo().maybe_preload(feed_for, [feed_publishes: [activity: [:verb, :object, subject_user: [:profile, :character]]]]) |> Map.get(:feed_publishes)
  # end

  @doc """
  Creates a new local activity and publishes to appropriate feeds
  """

  def publish(subject, verb, %{replied: %{reply_to_id: reply_to_id}} = object) when is_atom(verb) and is_binary(reply_to_id) do
    # publishing a reply to something
    # IO.inspect(publish_reply: object)
    do_publish(subject, verb, object, [Feeds.instance_feed_id(), creator_feed(object)])
  end

  def publish(subject, verb, %{tags: tags} = object) when is_atom(verb) and is_list(tags) do
    # publishing something with @ mentions or other tags
    # IO.inspect(publish_tagged: tags)
    do_publish(subject, verb, object, [Feeds.instance_feed_id(), tags_feed(tags)])
  end

  def publish(subject, verb, object) when is_atom(verb) do
    do_publish(subject, verb, object, Feeds.instance_feed_id())
  end

  @doc """
  Records a remote activity and puts in appropriate feeds
  """
  def save_fediverse_incoming_activity(subject, verb, object) when is_atom(verb) do
    do_publish(subject, verb, object, Feeds.fediverse_feed_id())
  end

  @doc """
  Creates a new local activity and publishes to creator's inbox
  """
  def maybe_notify_creator(subject, verb, object) when is_atom(verb) do

    do_put_in_feeds(subject, verb, object, creator_feed(object))
    # TODO: notify remote users via AP
  end

  def creator_feed(object) do
    object = object |> Bonfire.Repo.maybe_preload([creator_character: [:inbox]]) #|> IO.inspect

    Utils.e(object, :creator_character, :inbox, :feed_id, nil)
      || Feeds.inbox_feed_id(Utils.e(object, :creator_character, nil))
  end

  def tags_feed(tags) when is_list(tags), do: Enum.map(tags, fn x -> tags_feed(x) end)
  def tags_feed(%{character: character}) do
    character = character |> Bonfire.Repo.maybe_preload([:inbox]) #|> IO.inspect

    Utils.e(character, :inbox, :feed_id, nil)
      || Feeds.inbox_feed_id(character)
  end

  def maybe_notify_admins(subject, verb, object) when is_atom(verb) do
    admins = Bonfire.Me.Users.list_admins()

    inboxes = admins_inbox(admins) #|> IO.inspect

    do_put_in_feeds(subject, verb, object, inboxes)
    # TODO: notify remote users via AP
  end

  defp admins_inbox(admins) when is_list(admins), do: Enum.map(admins, fn x -> admins_inbox(x) end)
  defp admins_inbox(admin) do
    admin = admin |> Bonfire.Repo.maybe_preload(:inbox) #|> IO.inspect
    Utils.e(admin, :inbox, :feed_id, nil)
      || Feeds.inbox_feed_id(admin)
  end

  defp do_put_in_feeds(subject, verb, object, feed_id) when is_binary(feed_id) or is_list(feed_id) do
    with {:ok, activity} <- Activities.create(subject, verb, object),
    {:ok, published} <- feed_publish(feed_id, activity) # publish in specified feed
     do
      {:ok, published}
     else
      publishes when is_list(publishes) -> List.first(publishes)
    end
  end

  defp do_publish(subject, verb, object, feeds) when is_list(feeds), do: do_put_in_feeds(subject, verb, object, feeds ++ [subject])
  defp do_publish(subject, verb, object, feed_id), do: do_put_in_feeds(subject, verb, object, [feed_id, subject])
  defp do_publish(subject, verb, object), do: do_put_in_feeds(subject, verb, object, subject) # just publish to outbox

  defp feed_publish(feeds, activity) when is_list(feeds), do: Enum.map(feeds, fn x -> feed_publish(x, activity) end) # TODO: optimise?

  defp feed_publish(feed_or_subject, activity) do
    with {:ok, %{id: feed_id} = feed} <- Feeds.feed_for_id(feed_or_subject),
    {:ok, published} <- do_feed_publish(feed, activity) do

      published = %{published | activity: activity}

      # Utils.pubsub_broadcast(feed.id, {:feed_activity, activity}) # push to online users
      Utils.pubsub_broadcast(feed_id, published) # push to online users

      {:ok, published}
    end
  end

  defp do_feed_publish(%{id: feed_id}, %{id: activity_or_object_id}) do
    attrs = %{feed_id: feed_id, object_id: activity_or_object_id}
    repo().put(FeedPublish.changeset(attrs))
  end

  @doc "Delete an activity (usage by things like unlike)"
  def delete_for_object(%{id: id}), do: delete_for_object(id)
  def delete_for_object(id) when is_binary(id) and id !="", do: build_query(object_id: id) |> repo().delete_all() |> elem(1)
  def delete_for_object(ids) when is_list(ids), do: Enum.each(ids, fn x -> delete_for_object(x) end)
  def delete_for_object(_), do: nil


end
