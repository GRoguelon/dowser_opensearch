defmodule Dowser.Opensearch.AliasTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Alias
  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "update_aliases/2" do
    test "POSTs the actions to /_aliases, wrapped in an actions key" do
      {port, server} = start_server()

      actions = [%{"add" => %{"index" => "posts-v2", "alias" => "posts"}}]
      assert {:ok, _} = Alias.update_aliases(actions, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_aliases"
      assert req.body == ~s({"actions":[{"add":{"alias":"posts","index":"posts-v2"}}]})
    end

    test "keeps the order of the actions, so a remove/add swap stays atomic" do
      {port, server} = start_server()

      actions = [
        %{"remove" => %{"index" => "posts-v1", "alias" => "posts"}},
        %{"add" => %{"index" => "posts-v2", "alias" => "posts"}}
      ]

      assert {:ok, _} = Alias.update_aliases(actions, context: context(port))

      body = Task.await(server).body
      assert :binary.match(body, "remove") < :binary.match(body, "add")
    end

    test "accepts an empty action list" do
      {port, server} = start_server()

      assert {:ok, _} = Alias.update_aliases([], context: context(port))
      assert Task.await(server).body == ~s({"actions":[]})
    end
  end

  describe "put_alias/4" do
    test "PUTs /{index}/_alias/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = Alias.put_alias(%{}, "posts-v2", "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/posts-v2/_alias/posts"
    end

    test "sends a filter body" do
      {port, server} = start_server()

      body = %{"filter" => %{"term" => %{"status" => "published"}}}
      assert {:ok, _} = Alias.put_alias(body, "posts", "published", context: context(port))
      assert Task.await(server).body == ~s({"filter":{"term":{"status":"published"}}})
    end

    test "requires a name, naming it in the error" do
      assert {:error, %ArgumentError{} = error} = Alias.put_alias(%{}, "posts", nil)
      assert Exception.message(error) =~ "name is required"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = Alias.put_alias(%{}, nil, "posts")
      assert Exception.message(error) =~ "requires an index"
    end
  end

  describe "delete_alias/3" do
    test "DELETEs /{index}/_alias/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = Alias.delete_alias("posts-v1", "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/posts-v1/_alias/posts"
    end

    test "joins several indices and several names with commas" do
      {port, server} = start_server()

      assert {:ok, _} =
               Alias.delete_alias(["posts-v1", "posts-v2"], ["posts", "blog"],
                 context: context(port)
               )

      assert Task.await(server).path == "/posts-v1,posts-v2/_alias/posts,blog"
    end

    test "requires a name" do
      assert {:error, %ArgumentError{}} = Alias.delete_alias("posts", nil)
    end
  end

  describe "get_alias/1" do
    test "GETs /_alias for everything" do
      {port, server} = start_server()

      assert {:ok, _} = Alias.get_alias(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_alias"
    end

    test "restricts to a name" do
      {port, server} = start_server()

      assert {:ok, _} = Alias.get_alias(name: "posts", context: context(port))
      assert Task.await(server).path == "/_alias/posts"
    end

    test "combines an index and a name" do
      {port, server} = start_server()

      assert {:ok, _} = Alias.get_alias(index: "posts-v2", name: "posts", context: context(port))
      assert Task.await(server).path == "/posts-v2/_alias/posts"
    end

    test "rejects an empty name rather than silently dropping it" do
      assert {:error, %ArgumentError{} = error} = Alias.get_alias(name: "")
      assert Exception.message(error) =~ "name is required"
    end
  end

  describe "alias_exists/2" do
    test "HEADs /_alias/{name} and returns true on a 2xx" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert Alias.alias_exists("posts", context: context(port)) == {:ok, true}

      req = Task.await(server)
      assert req.method == "HEAD"
      assert req.path == "/_alias/posts"
    end

    test "returns false on a 404" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert Alias.alias_exists("missing", context: context(port)) == {:ok, false}

      Task.await(server)
    end

    test "scopes the check to an index" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert Alias.alias_exists("posts", index: "posts-v2", context: context(port)) == {:ok, true}
      assert Task.await(server).path == "/posts-v2/_alias/posts"
    end

    test "requires a name" do
      assert {:error, %ArgumentError{}} = Alias.alias_exists(nil)
    end

    test "alias_exists?/2 returns the bare boolean" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert Alias.alias_exists?("missing", context: context(port)) == false

      Task.await(server)
    end

    test "alias_exists?/2 raises on a genuine error rather than returning false" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> Alias.alias_exists?("posts", context: context(port)) end

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
