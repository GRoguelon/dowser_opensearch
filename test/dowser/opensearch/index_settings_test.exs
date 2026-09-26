defmodule Dowser.Opensearch.IndexSettingsTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.IndexSettings

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "put_settings/2" do
    test "PUTs the settings to /_settings for all indices" do
      {port, server} = start_server()

      settings = %{"index" => %{"number_of_replicas" => 2}}
      assert {:ok, _} = IndexSettings.put_settings(settings, context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_settings"
      assert req.body == ~s({"index":{"number_of_replicas":2}})
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = IndexSettings.put_settings(%{}, index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_settings"
    end

    test "joins several indices with commas" do
      {port, server} = start_server()

      assert {:ok, _} =
               IndexSettings.put_settings(%{},
                 index: ["posts", "comments"],
                 context: context(port)
               )

      assert Task.await(server).path == "/posts,comments/_settings"
    end

    test "sends a nil setting through, which is how a block is cleared" do
      {port, server} = start_server()

      settings = %{"index" => %{"blocks" => %{"write" => nil}}}
      assert {:ok, _} = IndexSettings.put_settings(settings, context: context(port))
      assert Task.await(server).body == ~s({"index":{"blocks":{"write":null}}})
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} =
               IndexSettings.put_settings(%{}, context: context(port))

      Task.await(server)
    end

    test "put_settings!/2 raises the error exception" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> IndexSettings.put_settings!(%{}, context: context(port)) end

      Task.await(server)
    end
  end

  describe "get_settings/1" do
    test "GETs /_settings for all indices" do
      {port, server} = start_server()

      assert {:ok, _} = IndexSettings.get_settings(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_settings"
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = IndexSettings.get_settings(index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_settings"
    end

    test "appends a setting name after the index" do
      {port, server} = start_server()

      assert {:ok, _} =
               IndexSettings.get_settings(
                 index: "posts",
                 name: "index.number_of_replicas",
                 context: context(port)
               )

      assert Task.await(server).path == "/posts/_settings/index.number_of_replicas"
    end

    test "joins several setting names with commas" do
      {port, server} = start_server()

      assert {:ok, _} =
               IndexSettings.get_settings(
                 name: ["index.refresh_interval", "index.blocks.write"],
                 context: context(port)
               )

      assert Task.await(server).path ==
               "/_settings/index.refresh_interval,index.blocks.write"
    end

    test "rejects an empty name rather than silently dropping it" do
      assert {:error, %ArgumentError{} = error} = IndexSettings.get_settings(name: "")
      assert Exception.message(error) =~ "name is required"
    end

    test "get_settings!/1 returns the body directly" do
      {port, server} = start_server()

      assert %{"acknowledged" => true} = IndexSettings.get_settings!(context: context(port))

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
