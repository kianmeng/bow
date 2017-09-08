defmodule Bow.EctoTest do
  use ExUnit.Case

  setup_all do
    Mix.Task.run "ecto.reset"
    Repo.start_link()
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

    :ok
  end

  setup do
    Bow.Storage.Local.reset!
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defmodule Avatar do
    use Bow.Uploader
    use Bow.Ecto

    def versions(_file) do
      [:original, :thumb]
    end

    def validate(%{ext: ".png"}), do: :ok
    def validate(_), do: {:error, "Only PNG allowed"}

    def store_dir(file) do
      "users/#{file.scope.id}"
    end
  end

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field :name,    :string
      field :avatar,  Avatar.Type
    end

    def changeset(struct \\ %__MODULE__{}, params) do
      struct
      |> Ecto.Changeset.cast(params, [:name, :avatar])
    end
  end

  @upload_bear %Plug.Upload{path: "test/files/bear.png", filename: "bear.png"}
  @upload_memo %Plug.Upload{path: "test/files/memo.txt", filename: "memo.txt"}

  describe "Type internals" do
    test "type/0" do
      assert Avatar.Type.type == :string
    end

    test "cast/1" do
      assert {:ok, %Bow{} = file} = Avatar.Type.cast(@upload_bear)
      assert file.name == "bear.png"
      assert file.path != nil
    end

    test "load/1" do
      assert {:ok, %Bow{} = file} = Avatar.Type.load("bear.png")
      assert file.name == "bear.png"
      assert file.path == nil
    end
  end

  describe "Custom cast" do
    defmodule Timestamp do
      use Bow.Uploader
      use Bow.Ecto

      def cast(file) do
        ts = DateTime.utc_now |> DateTime.to_unix
        Bow.set(file, :rootname, "avatar_#{ts}")
      end

      def store_dir(_file), do: "timestamp"
    end
  end

  describe "Inside schema" do
    test "do not store when not given" do
      assert {:ok, user, results} =
        User.changeset(%{"name" => "Jon"})
        |> Repo.insert!
        |> Bow.Ecto.store()

      assert user.avatar == nil
      assert results == []
    end

    test "cast when insert/update" do
      user = User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})

      assert %Bow{name: "bear.png"} = user.changes.avatar

      assert {:ok, user, results} =
        user
        |> Repo.insert!
        |> Bow.Ecto.store()

      assert results[:avatar] == {:ok, [original: :ok, thumb: :ok]}
      assert %Bow{name: "bear.png"} = user.avatar
      assert File.exists?("tmp/bow/users/#{user.id}/bear.png")

      assert Bow.url({user.avatar, user}) == "tmp/bow/users/#{user.id}/bear.png"
      assert Bow.url({user.avatar, user}, :thumb) == "tmp/bow/users/#{user.id}/thumb_bear.png"
    end

    test "load avatar" do
      # insert user with avatar
      User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
      |> Repo.insert!
      |> Bow.Ecto.store()

      # test loading
      user = Repo.one(User)
      assert %Bow{name: "bear.png", path: nil} = user.avatar
    end

    test "load when empty" do
      # insert user without
      User.changeset(%{"name" => "Jon"})
      |> Repo.insert!
      |> Bow.Ecto.store()

      # test loading
      user = Repo.one(User)
      assert user.avatar == nil
    end

    test "load with scope" do
      # insert user with avatar
      {:ok, user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!
        |> Bow.Ecto.store()

      # test load
      assert {:ok, file} = Bow.Ecto.load(user, :avatar)
      assert file.path == "tmp/bow/users/#{user.id}/bear.png"
    end

    test "delete when empty" do
      # insert user with avatar
      {:ok, _user, _} =
        User.changeset(%{"name" => "Jon"})
        |> Repo.insert!
        |> Bow.Ecto.store()

      # test delete
      assert {:ok, _user} =
        User
        |> Repo.one()
        |> Repo.delete!()
        |> Bow.Ecto.delete()
    end

    test "delete avatar" do
      # insert user with avatar
      {:ok, _user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!
        |> Bow.Ecto.store()

      # test delete
      assert {:ok, user} =
        User
        |> Repo.one()
        |> Repo.delete!()
        |> Bow.Ecto.delete()

      refute File.exists?("tmp/bow/users/#{user.id}/bear.png")
    end
  end

  describe "Validation" do
    test "allow empty file" do
      user =
        User.changeset(%{"name" => "Jon"})
        |> Bow.Ecto.validate()

      assert user.valid? == true
    end

    test "allow png file" do
      user =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Bow.Ecto.validate()

      assert user.valid? == true
    end

    test "do not allow txt file" do
      user =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_memo})
        |> Bow.Ecto.validate()

      assert user.valid? == false
      assert user.errors[:avatar] == {"Only PNG allowed", []}
    end
  end


#   import Mock

#   test_with_mock "remote_file_url handling", Bow.Download, [
#     get: fn _ ->
#       %{
#         status: 200,
#         body: "",
#         headers: %{"Content-Type" => "image/png"}
#       }
#     end
#   ] do
#     params = %{
#       "name" => "Jon",
#       "remote_avatar_url" => "http://img.example.com/file.png"
#     }
#
#     user = %MyUser{id: 1}
#       |> Bow.Ecto.cast_uploads(params, [:avatar])
#
#     assert %Bow{name: "file.png"} = user.changes.avatar
#   end
end