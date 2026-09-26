defmodule Dowser.Opensearch.MappingsTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.Mappings

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "put_mapping/3" do
    test "POSTs the mapping to /{index}/_mapping" do
      {port, server} = start_server()

      mapping = %{"properties" => %{"title" => %{"type" => "text"}}}
      assert {:ok, _} = Mappings.put_mapping(mapping, "posts", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/posts/_mapping"
      assert req.body == ~s({"properties":{"title":{"type":"text"}}})
    end

    test "joins several indices with commas" do
      {port, server} = start_server()

      assert {:ok, _} = Mappings.put_mapping(%{}, ["posts", "comments"], context: context(port))
      assert Task.await(server).path == "/posts,comments/_mapping"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = Mappings.put_mapping(%{}, nil)
      assert Exception.message(error) =~ "requires an index"
    end

    test "put_mapping!/3 raises when the index is missing" do
      assert_raise ArgumentError, ~r/requires an index/, fn ->
        Mappings.put_mapping!(%{}, nil)
      end
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} =
               Mappings.put_mapping(%{}, "posts", context: context(port))

      Task.await(server)
    end
  end

  describe "get_mapping/1" do
    test "GETs /_mapping for all indices" do
      {port, server} = start_server()

      assert {:ok, _} = Mappings.get_mapping(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_mapping"
    end

    test "targets an index" do
      {port, server} = start_server()

      assert {:ok, _} = Mappings.get_mapping(index: "posts", context: context(port))
      assert Task.await(server).path == "/posts/_mapping"
    end

    test "get_mapping!/1 returns the body directly" do
      {port, server} = start_server()

      assert %{"acknowledged" => true} = Mappings.get_mapping!(context: context(port))

      Task.await(server)
    end
  end

  describe "get_field_mapping/2" do
    test "GETs /_mapping/field/{fields}" do
      {port, server} = start_server()

      assert {:ok, _} = Mappings.get_field_mapping("title", context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_mapping/field/title"
    end

    test "joins several fields with commas, under an index" do
      {port, server} = start_server()

      assert {:ok, _} =
               Mappings.get_field_mapping(["title", "body"],
                 index: "posts",
                 context: context(port)
               )

      assert Task.await(server).path == "/posts/_mapping/field/title,body"
    end

    test "requires the fields, naming them in the error" do
      assert {:error, %ArgumentError{} = error} = Mappings.get_field_mapping(nil)
      assert Exception.message(error) =~ "fields is required"
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
