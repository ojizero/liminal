defmodule Liminal.Links.MassReindexerTest do
  use Liminal.DataCase, async: false

  import Ecto.Query

  alias Liminal.Accounts.Scope
  alias Liminal.Links
  alias Liminal.Links.{Link, MassReindexer}

  setup do
    user = Liminal.AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)
    reindexer_pid = start_reindexer!()

    on_exit(fn ->
      if Process.alive?(reindexer_pid), do: GenServer.stop(reindexer_pid, :normal, 5_000)
    end)

    {:ok, scope: scope, reindexer_pid: reindexer_pid}
  end

  describe "start_reindex/1" do
    test "queues only failed links for :failed mode", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, failed} = Links.create_link(scope, %{url: "https://failed.example.com"}, [tag.id])
      {:ok, indexed} = Links.create_link(scope, %{url: "https://indexed.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      Repo.update_all(from(l in Link, where: l.id == ^failed.id),
        set: [index_attempt_count: 2, index_last_attempted_at: now]
      )

      Repo.update_all(from(l in Link, where: l.id == ^indexed.id),
        set: [indexed_at: now]
      )

      assert {:ok, %{total: 1, mode: :failed}} = MassReindexer.start_reindex(:failed)
      assert %{status: :running, total: 1} = MassReindexer.status()
    end

    test "queues all links for :all mode", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)

      {:ok, _} = Links.create_link(scope, %{url: "https://one.example.com"}, [tag.id])
      {:ok, _} = Links.create_link(scope, %{url: "https://two.example.com"}, [tag.id])

      assert {:ok, %{total: 2, mode: :all}} = MassReindexer.start_reindex(:all)
    end

    test "returns error when a job is already running", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, _} = Links.create_link(scope, %{url: "https://busy.example.com"}, [tag.id])

      assert {:ok, _} = MassReindexer.start_reindex(:all)
      assert {:error, :already_running} = MassReindexer.start_reindex(:failed)
    end
  end

  describe "cancel/0" do
    test "stops a running job", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, _} = Links.create_link(scope, %{url: "https://cancel.example.com"}, [tag.id])

      assert {:ok, %{status: :running}} = MassReindexer.start_reindex(:all)
      assert :ok = MassReindexer.cancel()
      assert %{status: :idle} = MassReindexer.status()
    end
  end

  describe "list_mass_reindex_ids/1" do
    test ":failed excludes never-attempted unindexed links", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, fresh} = Links.create_link(scope, %{url: "https://fresh.example.com"}, [tag.id])
      {:ok, failed} = Links.create_link(scope, %{url: "https://retry.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      Repo.update_all(from(l in Link, where: l.id == ^failed.id),
        set: [index_attempt_count: 1, index_last_attempted_at: now]
      )

      ids = Links.list_mass_reindex_ids(:failed)

      assert failed.id in ids
      refute fresh.id in ids
    end
  end

  defp start_reindexer! do
    Application.put_env(:liminal, Liminal.Links.MassReindexer, batch_size: 10, interval_ms: 50)

    reindexer_pid = start_supervised!({MassReindexer, []})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), reindexer_pid)
    reindexer_pid
  end
end
