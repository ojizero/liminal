defmodule Liminal.Links.ExpiryPauseTest do
  use Liminal.DataCase, async: false

  import Liminal.AccountsFixtures
  import Liminal.LinksFixtures

  alias Liminal.Accounts
  alias Liminal.Accounts.Scope
  alias Liminal.Links
  alias Liminal.Links.ExpiryPause

  @day 86_400

  defp reload(user), do: Scope.for_user(Accounts.get_user!(user.id))

  describe "pause_expiries/2" do
    test "records the window and reports the user as paused" do
      scope = user_scope_fixture()

      assert {:ok, user} = Links.pause_expiries(scope, 30)
      assert Links.expiry_paused?(user)
      assert user.expiry_paused_at
      assert DateTime.diff(user.expiry_paused_until, user.expiry_paused_at) == 30 * @day
      assert Links.expiry_pause_resumes_at(user) == user.expiry_paused_until
    end

    test "rejects lengths outside the allowed range" do
      scope = user_scope_fixture()
      over_cap = Links.max_expiry_pause_days() + 1

      assert {:error, :invalid_duration} = Links.pause_expiries(scope, over_cap)
      assert {:error, :invalid_duration} = Links.pause_expiries(scope, 0)
      assert {:error, :invalid_duration} = Links.pause_expiries(scope, -5)
      assert {:error, :invalid_duration} = Links.pause_expiries(scope, "30")

      refute Links.expiry_paused?(reload(scope.user))
    end

    test "accepts the longest allowed length" do
      scope = user_scope_fixture()

      assert {:ok, user} = Links.pause_expiries(scope, Links.max_expiry_pause_days())
      assert Links.expiry_paused?(user)
    end

    test "re-times a running pause from its original start" do
      scope = user_scope_fixture()
      {:ok, paused} = Links.pause_expiries(scope, 7)
      aged = age_expiry_pause(paused, 2 * @day)

      assert {:ok, retimed} = Links.pause_expiries(Scope.for_user(aged), 30)
      assert retimed.expiry_paused_at == aged.expiry_paused_at
      assert DateTime.diff(retimed.expiry_paused_until, retimed.expiry_paused_at) == 30 * @day
    end

    test "a length shorter than the time already paused resumes instead" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{tag_ids: [tag_fixture(scope, %{expires_in_days: 30}).id]})
      [before] = link_tag_expiries(link)

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 10 * @day)

      assert {:ok, resumed} = Links.pause_expiries(Scope.for_user(aged), 1)
      refute Links.expiry_paused?(resumed)

      # The whole ten days count, not just the one day that was asked for.
      [shifted] = link_tag_expiries(link)
      assert DateTime.diff(shifted, before) == 10 * @day
    end
  end

  describe "resume_expiries/1" do
    test "moves tag deadlines forward by the time spent paused" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{tag_ids: [tag_fixture(scope, %{expires_in_days: 14}).id]})
      [before] = link_tag_expiries(link)

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 5 * @day)

      assert {:ok, resumed} = Links.resume_expiries(Scope.for_user(aged))
      refute Links.expiry_paused?(resumed)
      assert is_nil(resumed.expiry_paused_at)
      assert is_nil(resumed.expiry_paused_until)

      [shifted] = link_tag_expiries(link)
      assert DateTime.diff(shifted, before) == 5 * @day
    end

    test "moves viewed timestamps forward so the grace period is not consumed" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      {:ok, viewed} = Links.mark_viewed(scope, link)

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 3 * @day)

      assert {:ok, _resumed} = Links.resume_expiries(Scope.for_user(aged))

      refetched = Links.get_link!(scope, link.id)
      assert DateTime.diff(refetched.viewed_at, viewed.viewed_at) == 3 * @day
    end

    test "leaves deadlines alone when no time has been spent paused" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      [before] = link_tag_expiries(link)

      {:ok, paused} = Links.pause_expiries(scope, 7)
      assert {:ok, _resumed} = Links.resume_expiries(Scope.for_user(paused))

      assert link_tag_expiries(link) == [before]
    end

    test "is a no-op for a user who is not paused" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      [before] = link_tag_expiries(link)

      assert {:ok, user} = Links.resume_expiries(scope)
      refute Links.expiry_paused?(user)
      assert link_tag_expiries(link) == [before]
    end

    test "only touches the resuming user's links" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      other_link = link_fixture(other_scope)
      [other_before] = link_tag_expiries(other_link)

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 5 * @day)
      {:ok, _resumed} = Links.resume_expiries(Scope.for_user(aged))

      assert link_tag_expiries(other_link) == [other_before]
    end

    test "settles a window that already lapsed using only the paused time" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      [before] = link_tag_expiries(link)

      {:ok, paused} = Links.pause_expiries(scope, 2)
      aged = age_expiry_pause(paused, 6 * @day)

      assert {:ok, _resumed} = Links.resume_expiries(Scope.for_user(aged))

      # The pause only ran for its two days even though six have gone by since.
      [shifted] = link_tag_expiries(link)
      assert DateTime.diff(shifted, before) == 2 * @day
    end
  end

  describe "expiry_paused?/1" do
    test "is false with no pause, and for a window that has run out" do
      scope = user_scope_fixture()
      refute Links.expiry_paused?(scope)
      refute Links.expiry_paused?(nil)

      {:ok, paused} = Links.pause_expiries(scope, 7)
      assert Links.expiry_paused?(paused)

      assert paused |> lapse_expiry_pause() |> Links.expiry_paused?() == false
    end
  end

  describe "link_expires_at/2" do
    test "holds the remaining time steady while paused" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{tag_ids: [tag_fixture(scope, %{expires_in_days: 20}).id]})

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 8 * @day)
      link = Links.get_link!(scope, link.id)

      stored = Links.link_expires_at(link)
      effective = Links.link_expires_at(link, aged)

      assert DateTime.diff(effective, stored) == 8 * @day
    end

    test "matches the stored deadline once expiries are running again" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 4 * @day)
      {:ok, resumed} = Links.resume_expiries(Scope.for_user(aged))

      link = Links.get_link!(scope, link.id)
      assert Links.link_expires_at(link, resumed) == Links.link_expires_at(link)
    end
  end

  describe "writes made during a pause" do
    test "a tag applied while paused keeps its whole window on resume" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 14})

      {:ok, paused} = Links.pause_expiries(scope, 60)
      aged = age_expiry_pause(paused, 20 * @day)
      aged_scope = Scope.for_user(aged)

      link = link_fixture(aged_scope, %{tag_ids: [tag.id]})
      link = Links.get_link!(aged_scope, link.id)

      # Frozen at the full fourteen days for as long as the pause runs.
      assert_in_delta DateTime.diff(Links.link_expires_at(link, aged), DateTime.utc_now()),
                      14 * @day,
                      5

      {:ok, resumed} = Links.resume_expiries(aged_scope)

      assert_in_delta DateTime.diff(
                        Links.link_expires_at(Links.get_link!(scope, link.id), resumed),
                        DateTime.utc_now()
                      ),
                      14 * @day,
                      5
    end

    test "a link viewed while paused keeps its whole grace period on resume" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      grace = Application.get_env(:liminal, :viewed_grace_seconds, @day)

      {:ok, paused} = Links.pause_expiries(scope, 60)
      aged = age_expiry_pause(paused, 20 * @day)
      aged_scope = Scope.for_user(aged)

      {:ok, viewed} = Links.mark_viewed(aged_scope, link)

      assert_in_delta DateTime.diff(Links.link_expires_at(viewed, aged), DateTime.utc_now()),
                      grace,
                      5

      {:ok, resumed} = Links.resume_expiries(aged_scope)
      refetched = Links.get_link!(scope, link.id)

      assert_in_delta DateTime.diff(
                        Links.link_expires_at(refetched, resumed),
                        DateTime.utc_now()
                      ),
                      grace,
                      5
    end
  end

  describe "cleanup_expired/0" do
    test "keeps a paused user's overdue tags and links" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      set_link_tag_expiry(link, DateTime.add(DateTime.utc_now(:second), -1, :second))

      {:ok, _paused} = Links.pause_expiries(scope, 7)
      Links.cleanup_expired()

      assert Links.get_link!(scope, link.id)
    end

    test "keeps a paused user's stale viewed links" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      {:ok, _viewed} = Links.mark_viewed(scope, link)
      grace = Application.get_env(:liminal, :viewed_grace_seconds, @day)

      Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [viewed_at: DateTime.add(DateTime.utc_now(:second), -grace - 60, :second)]
      )

      {:ok, _paused} = Links.pause_expiries(scope, 7)
      Links.cleanup_expired()

      assert Links.get_link!(scope, link.id)
    end

    test "still sweeps users who are not paused" do
      paused_scope = user_scope_fixture()
      running_scope = user_scope_fixture()
      paused_link = link_fixture(paused_scope)
      running_link = link_fixture(running_scope)
      overdue = DateTime.add(DateTime.utc_now(:second), -1, :second)

      set_link_tag_expiry(paused_link, overdue)
      set_link_tag_expiry(running_link, overdue)
      {:ok, _paused} = Links.pause_expiries(paused_scope, 7)

      Links.cleanup_expired()

      assert Links.get_link!(paused_scope, paused_link.id)
      assert_raise Ecto.NoResultsError, fn -> Links.get_link!(running_scope, running_link.id) end
    end

    test "settles a lapsed pause before sweeping, sparing links that are not due yet" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      {:ok, paused} = Links.pause_expiries(scope, 10)
      # A ten day pause ran out a day ago and no sweep has happened since, so a link
      # that had five days left when it started still reads as six days overdue.
      aged = age_expiry_pause(paused, 11 * @day)
      set_link_tag_expiry(link, DateTime.add(aged.expiry_paused_at, 5 * @day, :second))
      assert DateTime.before?(hd(link_tag_expiries(link)), DateTime.utc_now())

      Links.cleanup_expired()

      assert Links.get_link!(scope, link.id)
      settled = Accounts.get_user!(scope.user.id)
      assert is_nil(settled.expiry_paused_at)
      assert is_nil(settled.expiry_paused_until)
    end

    test "sweeps links that were already due when a settled pause began" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      set_link_tag_expiry(link, DateTime.add(DateTime.utc_now(:second), -2 * @day, :second))

      {:ok, paused} = Links.pause_expiries(scope, 1)
      _lapsed = age_expiry_pause(paused, 2 * @day)

      Links.cleanup_expired()

      assert_raise Ecto.NoResultsError, fn -> Links.get_link!(scope, link.id) end
    end
  end

  describe "broadcasts" do
    test "announces pausing, resuming, and settling" do
      scope = user_scope_fixture()
      Links.subscribe_expiry_pause(scope)

      {:ok, paused} = Links.pause_expiries(scope, 7)
      assert_receive {:expiry_pause_changed, %{expiry_paused_until: until}}
      assert until == paused.expiry_paused_until

      {:ok, _resumed} = Links.resume_expiries(Scope.for_user(paused))
      assert_receive {:expiry_pause_changed, %{expiry_paused_until: nil}}

      {:ok, paused_again} = Links.pause_expiries(scope, 7)
      assert_receive {:expiry_pause_changed, _}

      _lapsed = lapse_expiry_pause(paused_again)
      Links.cleanup_expired()
      assert_receive {:expiry_pause_changed, %{expiry_paused_until: nil}}
    end
  end

  describe "user_stats/1" do
    test "holds the expiring counts steady while paused" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      set_link_tag_expiry(link, DateTime.add(DateTime.utc_now(:second), 24 * 3600, :second))

      assert Links.user_stats(scope).expiring_soon == 1

      {:ok, paused} = Links.pause_expiries(scope, 30)
      aged = age_expiry_pause(paused, 10 * @day)
      set_link_tag_expiry(link, DateTime.add(aged.expiry_paused_at, 24 * 3600, :second))

      # Ten days on, the stored deadline reads as nine days overdue; the pause holds
      # the link at the 24 hours it had left when counting stopped.
      assert DateTime.before?(hd(link_tag_expiries(link)), DateTime.utc_now())
      assert Links.user_stats(Scope.for_user(aged)).expiring_soon == 1
    end

    test "leaves paused users out of the instance-wide expiring counts" do
      admin_scope = admin_scope_fixture()
      scope = user_scope_fixture()
      link = link_fixture(scope)
      set_link_tag_expiry(link, DateTime.add(DateTime.utc_now(:second), 24 * 3600, :second))

      assert Links.instance_stats(admin_scope).expiring_soon == 1

      {:ok, _paused} = Links.pause_expiries(scope, 30)
      assert Links.instance_stats(admin_scope).expiring_soon == 0
    end
  end

  describe "ExpiryPause helpers" do
    test "offers durations within the cap, including the default" do
      days = Enum.map(ExpiryPause.duration_options(), &elem(&1, 1))

      assert Enum.all?(days, &(&1 >= 1 and &1 <= ExpiryPause.max_pause_days()))
      assert ExpiryPause.max_pause_days() in days
      assert ExpiryPause.default_pause_days() in days
    end

    test "reads a lapsed window as the length of the pause, not the time since" do
      scope = user_scope_fixture()
      {:ok, paused} = Links.pause_expiries(scope, 3)
      aged = age_expiry_pause(paused, 9 * @day)

      assert ExpiryPause.shift_seconds(aged) == 3 * @day
    end
  end
end
