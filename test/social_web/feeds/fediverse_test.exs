defmodule Bonfire.Social.Feeds.Fediverse.Test do

  use Bonfire.Social.ConnCase
  alias Bonfire.Social.Fake
  alias Bonfire.Social.Posts
  alias Bonfire.Social.Follows

  describe "show" do

    test "not logged in: fallback to instance feed" do
      conn = conn()
      conn = get(conn, "/browse/fediverse")
      doc = floki_response(conn) #|> IO.inspect
      # assert redirected_to(conn) =~ "/login"
      assert [_] = Floki.find(doc, "#tab-instance")
    end

    test "with account" do
      account = fake_account!()
      user = fake_user!(account)
      conn = conn(account: account)
      next = "/browse/fediverse"
      {view, doc} = floki_live(conn, next) #|> IO.inspect
      assert [_] = Floki.find(doc, "#tab-fediverse")
    end

    test "with user" do
      account = fake_account!()
      user = fake_user!(account)
      conn = conn(user: user, account: account)
      next = "/browse/fediverse"
      {view, doc} = floki_live(conn, next) #|> IO.inspect
      assert [_] = Floki.find(doc, "#tab-fediverse")
    end


    test "my own posts in fediverse feed (if activity_pub circle selected)" do
      account = fake_account!()
      user = fake_user!(account)
      attrs = %{circles: [:activity_pub], post_content: %{summary: "summary", name: "test post name", html_body: "<p>epic html message</p>"}}

      assert {:ok, post} = Posts.publish(user, attrs)
      assert post.post_content.name == "test post name"

      conn = conn(user: user, account: account)
      next = "/browse/fediverse"
      {view, doc} = floki_live(conn, next) #|> IO.inspect
      assert [feed] = Floki.find(doc, "#tab-fediverse")
      assert Floki.text(feed) =~ "test post name"
    end

    test "federated posts (which I am allowed to see) from people I am not following in fediverse feed" do
      user = fake_user!()

      account = fake_account!()
      user2 = fake_user!(account)

      attrs = %{circles: [:activity_pub, user2.id], post_content: %{summary: "summary", name: "test post name", html_body: "<p>epic html message</p>"}}

      assert {:ok, post} = Posts.publish(user, attrs)
      assert post.post_content.name == "test post name"

      conn = conn(user: user2, account: account)
      next = "/browse/fediverse"
      {view, doc} = floki_live(conn, next) #|> IO.inspect
      assert [feed] = Floki.find(doc, "#tab-fediverse")
      assert Floki.text(feed) =~ "test post name"

    end

  end

  describe "DO NOT show" do

    test "local-only posts in fediverse feed" do
      account = fake_account!()
      user = fake_user!(account)

      account2 = fake_account!()
      user2 = fake_user!(account2)
      Follows.follow(user2, user)

      attrs = %{circles: [:local], post_content: %{summary: "summary", name: "test post name", html_body: "<p>epic html message</p>"}}

      assert {:ok, post} = Posts.publish(user, attrs)
      assert post.post_content.name == "test post name"

      conn = conn(user: user2, account: account2)
      next = "/browse/fediverse"
      {view, doc} = floki_live(conn, next) #|> IO.inspect
      assert [feed] = Floki.find(doc, "#tab-fediverse")
      refute Floki.text(feed) =~ "test post name"
    end
  end

end
