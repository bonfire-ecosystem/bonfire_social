defmodule Bonfire.Social.Follows.Test do

  use Bonfire.Social.ConnCase
  alias Bonfire.Social.Fake
  alias Bonfire.Social.Posts
  alias Bonfire.Social.Follows


  describe "follow" do

    test "when I click follow on someone's profile" do
      some_account = fake_account!()
      someone = fake_user!(some_account)

      my_account = fake_account!()
      me = fake_user!(my_account)

      conn = conn(user: me, account: my_account)
      next = "/user/"<>someone.character.username
      {view, doc} = floki_live(conn, next) #|> IO.inspect

      assert follow = view |> element(".profile_follow") |> render_click()

      assert true == Follows.following?(me, someone)

      assert Floki.text(follow) =~ "Unfollow" # FIXME
    end

  end

  describe "unfollow" do

    test "when I click unfollow on someone's profile" do
      some_account = fake_account!()
      someone = fake_user!(some_account)

      my_account = fake_account!()
      me = fake_user!(my_account)

      assert {:ok, follow} = Follows.follow(me, someone)
      assert true == Follows.following?(me, someone)

      conn = conn(user: me, account: my_account)
      next = "/user/"<>someone.character.username
      {view, doc} = floki_live(conn, next) #|> IO.inspect

      assert unfollow = view |> element(".profile_follow") |> render_click()
      # FIXME
      assert false == Follows.following?(me, someone)

      assert Floki.text(unfollow) =~ "Follow"
    end
  end
end
