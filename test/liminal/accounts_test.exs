defmodule Liminal.AccountsTest do
  use Liminal.DataCase

  alias Liminal.Accounts

  import Liminal.AccountsFixtures
  alias Liminal.Accounts.{User, UserToken}

  describe "get_user_by_username/1" do
    test "does not return the user if the username does not exist" do
      refute Accounts.get_user_by_username("unknown_user")
    end

    test "returns the user if the username exists" do
      %{username: username} = user_fixture()
      assert %User{} = Accounts.get_user_by_username(username)
    end
  end

  describe "get_user_by_username_and_password/2" do
    test "does not return the user if the username does not exist" do
      refute Accounts.get_user_by_username_and_password("unknown_user", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_username_and_password(user.username, "invalid")
    end

    test "returns the user if the username and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_username_and_password(user.username, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(Ecto.UUID.generate())
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires username to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{username: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates username format" do
      {:error, changeset} = Accounts.register_user(%{username: "has spaces"})

      assert %{username: ["only letters, numbers, and underscores allowed"]} =
               errors_on(changeset)
    end

    test "validates username length" do
      {:error, changeset} = Accounts.register_user(%{username: "ab"})
      assert "should be at least 3 character(s)" in errors_on(changeset).username
    end

    test "validates username maximum length" do
      too_long = String.duplicate("a", 31)
      {:error, changeset} = Accounts.register_user(%{username: too_long})
      assert "should be at most 30 character(s)" in errors_on(changeset).username
    end

    test "validates username uniqueness" do
      %{username: username} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{username: username})
      assert "has already been taken" in errors_on(changeset).username
    end

    test "validates password when given" do
      {:error, changeset} = Accounts.register_user(%{username: "valid_user", password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "validates password confirmation matching" do
      {:error, changeset} =
        Accounts.register_user(%{
          username: "valid_user",
          password: "valid_password_123",
          password_confirmation: "different_password"
        })

      assert "does not match password" in errors_on(changeset).password_confirmation
    end

    test "registers users with confirmed_at set" do
      username = "test_user_123"
      {:ok, user} = Accounts.register_user(%{username: username, password: valid_user_password()})
      assert user.username == username
      assert user.confirmed_at != nil
      assert not is_nil(user.hashed_password)
      assert is_nil(user.password)
    end

    test "creates default tags for the user" do
      username = "test_user_456"
      {:ok, user} = Accounts.register_user(%{username: username, password: valid_user_password()})

      scope = Liminal.Accounts.Scope.for_user(user)
      tags = Liminal.Links.list_tags(scope)
      assert length(tags) == 3

      names = Enum.map(tags, & &1.name) |> Enum.sort()
      assert names == Enum.sort(["saved for later", "read later", "watch later"])
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_username_and_password(user.username, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "change_user_username/3" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = Accounts.change_user_username(%User{})
    end

    test "validates username format" do
      changeset = Accounts.change_user_username(%User{}, %{"username" => "has spaces"})

      assert %{username: ["only letters, numbers, and underscores allowed"]} =
               errors_on(changeset)
    end

    test "validates username length" do
      changeset = Accounts.change_user_username(%User{}, %{"username" => "ab"})
      assert %{username: ["should be at least 3 character(s)"]} = errors_on(changeset)
    end
  end

  describe "update_user_username/2" do
    setup do
      %{user: user_fixture()}
    end

    test "updates the username", %{user: user} do
      {:ok, updated} = Accounts.update_user_username(user, %{"username" => "new_name"})
      assert updated.username == "new_name"
    end

    test "returns error changeset on invalid username", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user_username(user, %{"username" => "bad name!"})

      assert %{username: [_]} = errors_on(changeset)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "list_users/1" do
    test "admin scope returns all users" do
      admin_scope = admin_scope_fixture()
      user1 = user_fixture(%{username: "alpha_user"})
      user2 = user_fixture(%{username: "beta_user"})

      users = Accounts.list_users(admin_scope)
      user_ids = Enum.map(users, & &1.id)

      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "non-admin scope raises" do
      scope = user_scope_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.list_users(scope)
      end
    end
  end

  describe "invite_user/2" do
    test "admin invites user with just username, returns user and token" do
      admin_scope = admin_scope_fixture()

      assert {:ok, {user, token}} =
               Accounts.invite_user(admin_scope, %{username: "invited_user"})

      assert user.username == "invited_user"
      assert user.role == "user"
      assert is_nil(user.hashed_password)
      assert user.confirmed_at != nil
      assert is_binary(token)
    end

    test "admin invites user with role admin" do
      admin_scope = admin_scope_fixture()

      assert {:ok, {user, _token}} =
               Accounts.invite_user(admin_scope, %{username: "invited_admin", role: "admin"})

      assert user.username == "invited_admin"
      assert user.role == "admin"
    end

    test "token resolves to the invited user" do
      admin_scope = admin_scope_fixture()

      {:ok, {user, token}} =
        Accounts.invite_user(admin_scope, %{username: "token_user"})

      assert found_user = Accounts.get_user_by_reset_password_token(token)
      assert found_user.id == user.id
    end

    test "creates default tags for invited user" do
      admin_scope = admin_scope_fixture()

      {:ok, {user, _token}} =
        Accounts.invite_user(admin_scope, %{username: "tagged_invite"})

      scope = Liminal.Accounts.Scope.for_user(user)
      tags = Liminal.Links.list_tags(scope)
      assert length(tags) == 3

      names = Enum.map(tags, & &1.name) |> Enum.sort()
      assert names == Enum.sort(["saved for later", "read later", "watch later"])
    end

    test "non-admin raises" do
      scope = user_scope_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.invite_user(scope, %{username: "nope"})
      end
    end

    test "invalid/duplicate username returns changeset error" do
      admin_scope = admin_scope_fixture()

      assert {:error, changeset} = Accounts.invite_user(admin_scope, %{})
      assert %{username: ["can't be blank"]} = errors_on(changeset)

      # Duplicate
      user_fixture(%{username: "taken_name"})

      assert {:error, changeset} =
               Accounts.invite_user(admin_scope, %{username: "taken_name"})

      assert "has already been taken" in errors_on(changeset).username
    end
  end

  describe "delete_own_account/1" do
    test "normal user can delete themselves" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      assert {:ok, deleted_user} = Accounts.delete_own_account(scope)
      assert deleted_user.id == user.id

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(user.id)
      end
    end

    test "admin can delete themselves if another admin exists" do
      _other_admin = admin_user_fixture(%{username: "other_admin"})
      admin = admin_user_fixture(%{username: "self_delete_admin"})
      scope = user_scope_fixture(admin)

      assert {:ok, deleted_user} = Accounts.delete_own_account(scope)
      assert deleted_user.id == admin.id
    end

    test "last admin gets :last_admin error" do
      admin = admin_user_fixture()
      scope = user_scope_fixture(admin)

      assert {:error, :last_admin} = Accounts.delete_own_account(scope)
    end
  end

  describe "step_down_from_admin/1" do
    test "admin steps down when another admin exists" do
      _other_admin = admin_user_fixture(%{username: "keeper_admin"})
      admin = admin_user_fixture(%{username: "stepping_down"})
      scope = user_scope_fixture(admin)

      assert {:ok, updated_user} = Accounts.step_down_from_admin(scope)
      assert updated_user.role == "user"
    end

    test "last admin gets :last_admin error" do
      admin = admin_user_fixture()
      scope = user_scope_fixture(admin)

      assert {:error, :last_admin} = Accounts.step_down_from_admin(scope)
    end

    test "non-admin gets :not_admin error" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      assert {:error, :not_admin} = Accounts.step_down_from_admin(scope)
    end
  end

  describe "disable_user/2 and enable_user/2" do
    test "admin disables a user" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      assert {:ok, disabled_user} = Accounts.disable_user(admin_scope, user)
      assert disabled_user.disabled_at != nil
    end

    test "admin enables a disabled user" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      {:ok, disabled_user} = Accounts.disable_user(admin_scope, user)
      assert disabled_user.disabled_at != nil

      assert {:ok, enabled_user} = Accounts.enable_user(admin_scope, disabled_user)
      assert enabled_user.disabled_at == nil
    end

    test "raises when targeting admin" do
      admin_scope = admin_scope_fixture()
      admin = admin_user_fixture()

      assert_raise RuntimeError, "cannot modify admin user", fn ->
        Accounts.disable_user(admin_scope, admin)
      end

      assert_raise RuntimeError, "cannot modify admin user", fn ->
        Accounts.enable_user(admin_scope, admin)
      end
    end

    test "non-admin raises" do
      scope = user_scope_fixture()
      user = user_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.disable_user(scope, user)
      end

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.enable_user(scope, user)
      end
    end
  end

  describe "delete_user/2" do
    test "admin deletes a user" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      assert {:ok, deleted_user} = Accounts.delete_user(admin_scope, user)
      assert deleted_user.id == user.id

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(user.id)
      end
    end

    test "raises when targeting admin" do
      admin_scope = admin_scope_fixture()
      admin = admin_user_fixture()

      assert_raise RuntimeError, "cannot modify admin user", fn ->
        Accounts.delete_user(admin_scope, admin)
      end
    end

    test "non-admin raises" do
      scope = user_scope_fixture()
      user = user_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.delete_user(scope, user)
      end
    end
  end

  describe "promote_user/2" do
    test "admin promotes user to admin" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      assert {:ok, promoted_user} = Accounts.promote_user(admin_scope, user)
      assert promoted_user.role == "admin"
    end

    test "raises when targeting admin" do
      admin_scope = admin_scope_fixture()
      admin = admin_user_fixture()

      assert_raise RuntimeError, "cannot modify admin user", fn ->
        Accounts.promote_user(admin_scope, admin)
      end
    end

    test "non-admin raises" do
      scope = user_scope_fixture()
      user = user_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.promote_user(scope, user)
      end
    end
  end

  describe "demote_user/2" do
    test "admin demotes another admin to user" do
      admin_scope = admin_scope_fixture()
      target_admin = admin_user_fixture()

      assert {:ok, user} = Accounts.demote_user(admin_scope, target_admin)
      assert user.role == "user"
    end

    test "returns error when target is not an admin" do
      admin_scope = admin_scope_fixture()
      regular_user = user_fixture()

      assert {:error, :not_admin} = Accounts.demote_user(admin_scope, regular_user)
    end

    test "returns error when trying to demote self" do
      # Create two admins so the target isn't the last admin
      admin = admin_user_fixture()
      scope = user_scope_fixture(admin)
      _other_admin = admin_user_fixture()

      assert {:error, :self_demotion} = Accounts.demote_user(scope, admin)
    end

    test "returns error when demoting last admin" do
      scope_admin = admin_user_fixture()
      scope = user_scope_fixture(scope_admin)
      target_admin = admin_user_fixture()

      # Make scope_admin no longer admin in DB so target is the last admin
      # The scope struct still has role "admin" so ensure_admin! passes
      Liminal.Repo.update!(Ecto.Changeset.change(scope_admin, role: "user"))

      assert {:error, :last_admin} = Accounts.demote_user(scope, target_admin)
    end

    test "non-admin scope raises" do
      scope = user_scope_fixture()
      target_admin = admin_user_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.demote_user(scope, target_admin)
      end
    end
  end

  describe "generate_reset_password_token/2" do
    test "admin generates token for user, returns encoded string" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      encoded_token = Accounts.generate_reset_password_token(admin_scope, user)
      assert is_binary(encoded_token)
      assert {:ok, _raw} = Base.url_decode64(encoded_token, padding: false)

      # Token can be used to look up the user
      assert found_user = Accounts.get_user_by_reset_password_token(encoded_token)
      assert found_user.id == user.id
    end

    test "deletes previous reset tokens for same user" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      first_token = Accounts.generate_reset_password_token(admin_scope, user)
      _second_token = Accounts.generate_reset_password_token(admin_scope, user)

      # First token should no longer be valid
      refute Accounts.get_user_by_reset_password_token(first_token)
    end

    test "raises when targeting admin" do
      admin_scope = admin_scope_fixture()
      admin = admin_user_fixture()

      assert_raise RuntimeError, "cannot modify admin user", fn ->
        Accounts.generate_reset_password_token(admin_scope, admin)
      end
    end

    test "non-admin raises" do
      scope = user_scope_fixture()
      user = user_fixture()

      assert_raise RuntimeError, "admin required", fn ->
        Accounts.generate_reset_password_token(scope, user)
      end
    end
  end

  describe "get_user_by_reset_password_token/1" do
    test "valid token returns user" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      encoded_token = Accounts.generate_reset_password_token(admin_scope, user)
      assert found_user = Accounts.get_user_by_reset_password_token(encoded_token)
      assert found_user.id == user.id
    end

    test "expired token returns nil" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      encoded_token = Accounts.generate_reset_password_token(admin_scope, user)

      # Decode the encoded token to get raw binary for offset_user_token
      {:ok, raw_token} = Base.url_decode64(encoded_token, padding: false)
      offset_user_token(raw_token, -2, :day)

      refute Accounts.get_user_by_reset_password_token(encoded_token)
    end

    test "invalid token returns nil" do
      refute Accounts.get_user_by_reset_password_token("invalid_token")
    end

    test "disabled user returns nil" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      encoded_token = Accounts.generate_reset_password_token(admin_scope, user)
      {:ok, _disabled_user} = Accounts.disable_user(admin_scope, user)

      refute Accounts.get_user_by_reset_password_token(encoded_token)
    end
  end

  describe "reset_user_password/2" do
    test "valid params update password and delete all tokens" do
      user = user_fixture()

      # Generate a session token first to verify deletion
      _session_token = Accounts.generate_user_session_token(user)
      assert Repo.get_by(UserToken, user_id: user.id)

      assert {:ok, {updated_user, expired_tokens}} =
               Accounts.reset_user_password(user, %{password: "new valid password"})

      assert is_nil(updated_user.password)
      assert expired_tokens != []
      refute Repo.get_by(UserToken, user_id: user.id)

      assert Accounts.get_user_by_username_and_password(
               updated_user.username,
               "new valid password"
             )
    end

    test "invalid params return changeset errors" do
      user = user_fixture()

      assert {:error, changeset} = Accounts.reset_user_password(user, %{password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end
  end

  describe "get_user_by_username_and_password/2 (disabled check)" do
    test "disabled user returns nil even with correct password" do
      admin_scope = admin_scope_fixture()
      user = user_fixture() |> set_password()

      # Verify login works before disabling
      assert Accounts.get_user_by_username_and_password(user.username, valid_user_password())

      {:ok, _disabled_user} = Accounts.disable_user(admin_scope, user)

      refute Accounts.get_user_by_username_and_password(user.username, valid_user_password())
    end
  end

  describe "session invalidation for disabled users" do
    test "disabled user's session token no longer resolves" do
      admin_scope = admin_scope_fixture()
      user = user_fixture()

      token = Accounts.generate_user_session_token(user)
      assert Accounts.get_user_by_session_token(token)

      {:ok, _disabled_user} = Accounts.disable_user(admin_scope, user)

      refute Accounts.get_user_by_session_token(token)
    end
  end
end
