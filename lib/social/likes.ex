defmodule Bonfire.Social.Likes do

  alias Bonfire.Data.Identity.User
  alias Bonfire.Data.Social.Like
  alias Bonfire.Data.Social.LikeCount
  alias Bonfire.Social.{Activities, FeedActivities}
  import Ecto.Query
  import Bonfire.Me.Integration
  alias Bonfire.Common.Utils

  def liked?(%User{}=user, liked), do: not is_nil(get!(user, liked))
  def get(%User{}=user, liked), do: repo().single(by_both_q(user, liked))
  def get!(%User{}=user, liked), do: repo().one(by_both_q(user, liked))
  def by_liker(%User{}=user), do: repo().all(by_liker_q(user))
  def by_liked(%User{}=user), do: repo().all(by_liked_q(user))
  def by_any(%User{}=user), do: repo().all(by_any_q(user))

  def like(%User{} = liker, %{} = liked) do
    with {:ok, like} <- create(liker, liked) do
      # TODO: increment the like count
      FeedActivities.maybe_notify_creator(liker, :like, liked)
      {:ok, like}
    end
  end
  def like(%User{} = liker, liked) when is_binary(liked) do
    with {:ok, liked} <- Bonfire.Common.Pointers.get(liked) do
      # IO.inspect(liked)
      like(liker, liked)
    end
  end

  def unlike(%User{}=liker, %{}=liked) do
    delete_by_both(liker, liked) # delete the Like
    Activities.delete_by_subject_verb_object(liker, :like, liked) # delete the like activity & feed entries
    # TODO: decrement the like count
  end
  def unlike(%User{} = liker, liked) when is_binary(liked) do
    with {:ok, liked} <- Bonfire.Common.Pointers.get(liked) do
      unlike(liker, liked)
    end
  end

  @doc "List likes by the user and which are in their outbox"
  def list_by(by_user, current_user \\ nil, cursor_before \\ nil, preloads \\ :all) when is_binary(by_user) or is_list(by_user) do

    # query FeedPublish
    FeedActivities.build_query(feed_id: by_user, likes_by: by_user)
    |> FeedActivities.feed_query_paginated(current_user, cursor_before, preloads)
  end

  defp create(%{} = liker, %{} = liked) do
    changeset(liker, liked) |> repo().insert()
  end

  defp changeset(%{id: liker}, %{id: liked}) do
    Like.changeset(%Like{}, %{liker_id: liker, liked_id: liked})
  end

  @doc "Delete likes where i am the liker"
  defp delete_by_liker(%User{}=me), do: elem(repo().delete_all(by_liker_q(me)), 1)

  @doc "Delete likes where i am the liked"
  defp delete_by_liked(%User{}=me), do: elem(repo().delete_all(by_liked_q(me)), 1)

  @doc "Delete likes where i am the liker or the liked."
  defp delete_by_any(%User{}=me), do: elem(repo().delete_all(by_any_q(me)), 1)

  @doc "Delete likes where i am the liker and someone else is the liked."
  defp delete_by_both(%User{}=me, %{}=liked), do: elem(repo().delete_all(by_both_q(me, liked)), 1)

  def by_liker_q(%User{id: id}) do
    from f in Like,
      where: f.liker_id == ^id,
      select: f.id
  end

  def by_liked_q(%User{id: id}) do
    from f in Like,
      where: f.liked_id == ^id,
      select: f.id
  end

  def by_any_q(%User{id: id}) do
    from f in Like,
      where: f.liker_id == ^id or f.liked_id == ^id,
      select: f.id
  end

  def by_both_q(%User{id: liker}, %{id: liked}), do: by_both_q(liker, liked)

  def by_both_q(liker, liked) when is_binary(liker) and is_binary(liked) do
    from f in Like,
      where: f.liker_id == ^liker or f.liked_id == ^liked,
      select: f.id
  end

end
