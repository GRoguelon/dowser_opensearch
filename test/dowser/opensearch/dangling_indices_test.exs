defmodule Dowser.Opensearch.DanglingIndicesTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.DanglingIndices
  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub

  @uuid "zmM4e0JtBkeUjiHD-MihPQ"

  @listing ~s({"dangling_indices":[{"index_name":"posts","index_uuid":"#{@uuid}"}]})
  @listing_response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@listing)}\r\n\r\n" <>
                      @listing

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "list/1" do
    test "GETs /_dangling and decodes the listing" do
      {port, server} = start_server(@listing_response)

      assert {:ok, body} = DanglingIndices.list(context: context(port))
      assert [%{"index_uuid" => @uuid}] = body["dangling_indices"]

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_dangling"
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = DanglingIndices.list(context: context(port))

      Task.await(server)
    end

    test "list!/1 returns the body directly" do
      {port, server} = start_server(@listing_response)

      assert %{"dangling_indices" => [_]} = DanglingIndices.list!(context: context(port))

      Task.await(server)
    end
  end

  describe "import_dangling_index/3" do
    test "POSTs /_dangling/{index_uuid} with accept_data_loss" do
      {port, server} = start_server()

      assert {:ok, _} = DanglingIndices.import_dangling_index(@uuid, true, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_dangling/#{@uuid}?accept_data_loss=true"
    end

    test "sends accept_data_loss=false as given, letting OpenSearch reject it" do
      {port, server} = start_server()

      assert {:ok, _} =
               DanglingIndices.import_dangling_index(@uuid, false, context: context(port))

      assert Task.await(server).path == "/_dangling/#{@uuid}?accept_data_loss=false"
    end

    test "preserves other params alongside accept_data_loss" do
      {port, server} = start_server()

      assert {:ok, _} =
               DanglingIndices.import_dangling_index(@uuid, true,
                 params: [timeout: "30s"],
                 context: context(port)
               )

      assert Task.await(server).path ==
               "/_dangling/#{@uuid}?timeout=30s&accept_data_loss=true"
    end

    test "requires an index_uuid, naming it in the error" do
      assert {:error, %ArgumentError{} = error} = DanglingIndices.import_dangling_index(nil, true)
      assert Exception.message(error) =~ "index_uuid is required"
    end

    test "rejects a non-boolean accept_data_loss at the call site" do
      assert_raise FunctionClauseError, fn ->
        DanglingIndices.import_dangling_index(@uuid, "true")
      end
    end
  end

  describe "delete_dangling_index/3" do
    test "DELETEs /_dangling/{index_uuid} with accept_data_loss" do
      {port, server} = start_server()

      assert {:ok, _} = DanglingIndices.delete_dangling_index(@uuid, true, context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_dangling/#{@uuid}?accept_data_loss=true"
    end

    test "requires an index_uuid" do
      assert {:error, %ArgumentError{}} = DanglingIndices.delete_dangling_index(nil, true)
    end

    test "delete_dangling_index!/3 raises when the uuid is missing" do
      assert_raise ArgumentError, ~r/index_uuid is required/, fn ->
        DanglingIndices.delete_dangling_index!(nil, true)
      end
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
