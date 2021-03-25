defmodule Bonfire.Social.Boosts do

  alias Bonfire.Data.Identity.User
  alias Bonfire.Data.Social.Boost
  alias Bonfire.Data.Social.BoostCount
  alias Bonfire.Social.{Activities, FeedActivities}
  import Ecto.Query
  import Bonfire.Me.Integration
  alias Bonfire.Common.Utils

  def boosted?(%User{}=user, boosted), do: not is_nil(get!(user, boosted))
  def get(%User{}=user, boosted), do: repo().single(by_both_q(user, boosted))
  def get!(%User{}=user, boosted), do: repo().one(by_both_q(user, boosted))
  def by_booster(%User{}=user), do: repo().all(by_booster_q(user))
  def by_boosted(%User{}=user), do: repo().all(by_boosted_q(user))
  def by_any(%User{}=user), do: repo().all(by_any_q(user))

  def boost(%User{} = booster, %{} = boosted) do
    with {:ok, boost} <- create(booster, boosted),
    {:ok, published} <- FeedActivities.publish(booster, :boost, boosted) do
      # TODO: increment the boost count

      FeedActivities.maybe_notify_creator(published, boosted) #|> IO.inspect

      {:ok, boost}
    end
  end
  def boost(%User{} = booster, boosted) when is_binary(boosted) do
    with {:ok, boosted} <- Bonfire.Common.Pointers.get(boosted) do
      # IO.inspect(liked)
      boost(booster, boosted)
    end
  end

  def unboost(%User{}=booster, %{}=boosted) do
    delete_by_both(booster, boosted) # delete the Boost
    Activities.delete_by_subject_verb_object(booster, :boost, boosted) # delete the boost activity & feed entries
    # TODO: decrement the boost count
  end
  def unboost(%User{} = booster, boosted) when is_binary(boosted) do
    with {:ok, boosted} <- Bonfire.Common.Pointers.get(boosted) do
      # IO.inspect(liked)
      unboost(booster, boosted)
    end
  end

  @doc "List boosts by the user and which are in their outbox"
  def list_by(by_user, current_user \\ nil, cursor_before \\ nil, preloads \\ :all) when is_binary(by_user) or is_list(by_user) do

    # query FeedPublish
    FeedActivities.build_query(feed_id: by_user, boosts_by: by_user)
    |> FeedActivities.feed_query_paginated(current_user, cursor_before, preloads)
  end

  defp create(%{} = booster, %{} = boosted) do
    changeset(booster, boosted) |> repo().insert()
  end

  defp changeset(%{id: booster}, %{id: boosted}) do
    Boost.changeset(%Boost{}, %{booster_id: booster, boosted_id: boosted})
  end

  @doc "Delete boosts where i am the booster"
  defp delete_by_booster(%User{}=me), do: elem(repo().delete_all(by_booster_q(me)), 1)

  @doc "Delete boosts where i am the boosted"
  defp delete_by_boosted(%User{}=me), do: elem(repo().delete_all(by_boosted_q(me)), 1)

  @doc "Delete boosts where i am the booster or the boosted."
  defp delete_by_any(%User{}=me), do: elem(repo().delete_all(by_any_q(me)), 1)

  @doc "Delete boosts where i am the booster and someone else is the boosted."
  defp delete_by_both(%User{}=me, %{}=boosted), do: elem(repo().delete_all(by_both_q(me, boosted)), 1)

  def by_booster_q(%User{id: id}) do
    from f in Boost,
      where: f.booster_id == ^id,
      select: f.id
  end

  def by_boosted_q(%User{id: id}) do
    from f in Boost,
      where: f.boosted_id == ^id,
      select: f.id
  end

  def by_any_q(%User{id: id}) do
    from f in Boost,
      where: f.booster_id == ^id or f.boosted_id == ^id,
      select: f.id
  end

  def by_both_q(%User{id: booster}, %{id: boosted}), do: by_both_q(booster, boosted)

  def by_both_q(booster, boosted) when is_binary(booster) and is_binary(boosted) do
    from f in Boost,
      where: f.booster_id == ^booster or f.boosted_id == ^boosted,
      select: f.id
  end

end
