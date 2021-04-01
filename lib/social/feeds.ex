defmodule Bonfire.Social.Feeds do

  alias Bonfire.Data.Social.{Feed, FeedPublish, Inbox}
  alias Bonfire.Data.Identity.{User}
  alias Bonfire.Social.{Activities, Follows}
  alias Ecto.Changeset
  import Ecto.Query
  import Bonfire.Me.Integration
  alias Bonfire.Common.Utils

  def instance_feed_id, do: Bonfire.Boundaries.Circles.circles[:local]
  def fediverse_feed_id, do: Bonfire.Boundaries.Circles.circles[:activity_pub]

  def my_feed_ids(%{} = user, extra_feeds \\ []) do
    extra_feeds = extra_feeds ++ [user.id]
    with following_ids when is_list(following_ids) <- Follows.by_follower(user) do
      #IO.inspect(subs: following_ids)
      extra_feeds ++ following_ids
    else
      _e ->
        #IO.inspect(e: e)
        extra_feeds
    end
  end

  def my_feed_ids(_, extra_feeds), do: extra_feeds

  def my_inbox_feed_id(%{current_user: %{character: %{inbox: %{feed_id: feed_id}}}, current_account:  %{inbox: %{feed_id: account_feed_id}}}) when is_binary(feed_id) do
    [feed_id, account_feed_id]
  end
  def my_inbox_feed_id(%{current_user: %{character: %{inbox: %{feed_id: feed_id}}}}) when is_binary(feed_id) do
    feed_id
  end
  def my_inbox_feed_id(%{current_user: user}) when not is_nil(user) do
    inbox_feed_id(user)
  end
  def my_inbox_feed_id(%{current_account: %{inbox: %{feed_id: account_feed_id}}}) when is_binary(account_feed_id) do
    account_feed_id
  end
  def my_inbox_feed_id(%{current_account: account}) when not is_nil(account) do
    inbox_feed_id(account)
  end

  def inbox_feed_id(%{} = for_subject) do
    with {:ok, %{feed_id: feed_id} = inbox} <- create_inbox(for_subject) do
      feed_id
    end
  end
  def inbox_feed_id(_) do
    nil
  end

  def creator_feed(object) do
    object = object |> Bonfire.Repo.maybe_preload([created: [creator_character: [:inbox]]]) #|> IO.inspect

    Utils.e(object, :created, :creator_character, :inbox, :feed_id, nil)
      || inbox_feed_id(Utils.e(object, :created, :creator_character, nil)) #|> IO.inspect
  end

  def tags_feed(tags) when is_list(tags), do: Enum.map(tags, fn x -> tags_feed(x) end)
  def tags_feed(%{character: character}) do
    character = character |> Bonfire.Repo.maybe_preload([:inbox]) #|> IO.inspect

    Utils.e(character, :inbox, :feed_id, nil)
      || inbox_feed_id(character)
  end

  def admins_inbox(), do: Bonfire.Me.Users.list_admins() |> admins_inbox()
  def admins_inbox(admins) when is_list(admins), do: Enum.map(admins, fn x -> admins_inbox(x) end)
  def admins_inbox(admin) do
    admin = admin |> Bonfire.Repo.maybe_preload([character: [:inbox]]) # |> IO.inspect
    Utils.e(admin, :character, :inbox, :feed_id, nil)
      || inbox_feed_id(admin)
  end


  @doc """
  Create a OUTBOX feed for an existing Pointable (eg. User)
  """
  def create(%{id: id}=_thing) do
    do_create(%{id: id})
  end

  @doc """
  Create a INBOX feed for an existing Pointable (eg. User)
  """
  def create_inbox(%{id: id}=_thing) do
    with {:ok, %{id: feed_id} = feed} <- create() do
      #IO.inspect(feed: feed)
      do_create_inbox(%{id: id, feed_id: feed_id})
    end
  end

  @doc """
  Create a new generic feed
  """
  def create() do
    do_create(%{})
  end

  defp do_create(attrs) do
    repo().put(changeset(attrs))
  end

  def changeset(activity \\ %Feed{}, %{} = attrs) do
    Feed.changeset(activity, attrs)
  end

  defp do_create_inbox(attrs) do
    repo().upsert(Inbox.changeset(attrs))
  end

  @doc """
  Get or create feed for something
  """
  def feed_for_id(%Feed{id: _} = feed), do: feed
  def feed_for_id(%{id: subject_id}), do: feed_for_id(subject_id)
  def feed_for_id(subject_id) when is_binary(subject_id) do
    with {:error, _} <- repo().single(feed_for_id_query(subject_id)) do
      create(%{id: subject_id})
    end
  end
  def feed_for_id(_), do: nil

  def feed_for_id_query(subject_id) do
    from f in Feed,
     where: f.id == ^subject_id
  end


end
