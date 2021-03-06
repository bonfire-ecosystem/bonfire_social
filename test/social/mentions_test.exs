defmodule Bonfire.Social.MentionsTest do
  use Bonfire.DataCase

  alias Bonfire.Social.{Posts, Feeds, FeedActivities}
  alias Bonfire.Me.Fake

  test "can post with a mention" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    msg = "hey @#{mentioned.character.username} you have an epic text message"
    attrs = %{post_content: %{html_body: msg}}
    assert {:ok, post} = Posts.publish(me, attrs)

    assert String.contains?(post.post_content.html_body, "epic text message")
  end

  test "can see post mentioning me in my notifications (with private mentions turned off)" do
    poster = Fake.fake_user!()
    me = Fake.fake_user!()
    attrs = %{post_content: %{html_body: "<p>hey @#{me.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(poster, attrs, false)

    assert %{entries: feed} = FeedActivities.feed(:notifications, me)
    fp = List.first(feed)

    assert fp.activity.id == mention.activity.id
  end

  test "mentioning someone does not appear in my own notifications" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs)

    assert %{entries: []} = FeedActivities.feed(:notifications, me)
  end

  test "mentioning someone else does not appear in a 3rd party's notifications" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs)

    third = Fake.fake_user!()

    assert %{entries: []} = FeedActivities.feed(:notifications, third)
  end

  test "mentioning someone appears in their feed" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs, false)

    assert %{entries: feed} = FeedActivities.my_feed(mentioned)
    fp = List.first(feed)

    assert fp.activity.id == mention.activity.id
  end

  test "mentioning someone DOES NOT appear (with private mentions turned off) in their instance feed" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs, false)

    feed_id = Bonfire.Social.Feeds.instance_feed_id()

    assert %{entries: []} = FeedActivities.feed(feed_id, mentioned)
  end

  test "mentioning someone appears in my instance feed, if included in circles" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{circles: [Bonfire.Social.Feeds.instance_feed_id()], post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs)

    feed_id = Bonfire.Social.Feeds.instance_feed_id()

    assert %{entries: feed} = FeedActivities.feed(feed_id, me)
    fp = List.first(feed)

    assert fp.activity.id == mention.activity.id
  end

  test "mentioning someone does not appear in a 3rd party's instance feed" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs)

    third = Fake.fake_user!()

    feed_id = Bonfire.Social.Feeds.instance_feed_id()

    assert %{entries: []} = FeedActivities.feed(feed_id, third)
  end

  test "mentioning someone does not appear in the public instance feed" do
    me = Fake.fake_user!()
    mentioned = Fake.fake_user!()
    attrs = %{circles: [Bonfire.Social.Feeds.instance_feed_id()], post_content: %{html_body: "<p>hey @#{mentioned.character.username} you have an epic html message</p>"}}

    assert {:ok, mention} = Posts.publish(me, attrs)

    feed_id = Bonfire.Social.Feeds.instance_feed_id()

    assert %{entries: []} = FeedActivities.feed(feed_id, nil)
  end


end
