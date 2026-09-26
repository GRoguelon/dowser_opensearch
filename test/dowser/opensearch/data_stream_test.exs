defmodule Dowser.Opensearch.DataStreamTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.DataStream
  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "create_data_stream/2" do
    test "PUTs /_data_stream/{name} with no body" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.create_data_stream("logs", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_data_stream/logs"
      assert req.body == ""
    end

    test "requires a name" do
      assert {:error, %ArgumentError{} = error} = DataStream.create_data_stream(nil)
      assert Exception.message(error) =~ "name is required"
    end

    test "create_data_stream!/2 raises when the name is missing" do
      assert_raise ArgumentError, ~r/name is required/, fn ->
        DataStream.create_data_stream!(nil)
      end
    end
  end

  describe "get_data_stream/1" do
    test "GETs /_data_stream for all streams" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.get_data_stream(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_data_stream"
    end

    test "appends a name" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.get_data_stream(name: "logs", context: context(port))
      assert Task.await(server).path == "/_data_stream/logs"
    end

    test "accepts a wildcard and several names" do
      {port, server} = start_server()

      assert {:ok, _} =
               DataStream.get_data_stream(name: ["logs-*", "metrics"], context: context(port))

      assert Task.await(server).path == "/_data_stream/logs-*,metrics"
    end

    test "rejects an empty name rather than silently listing everything" do
      assert {:error, %ArgumentError{}} = DataStream.get_data_stream(name: "")
    end
  end

  describe "delete_data_stream/2" do
    test "DELETEs /_data_stream/{name}" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.delete_data_stream("logs", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_data_stream/logs"
    end

    test "requires a name" do
      assert {:error, %ArgumentError{}} = DataStream.delete_data_stream(nil)
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} =
               DataStream.delete_data_stream("logs", context: context(port))

      Task.await(server)
    end
  end

  describe "data_streams_stats/1" do
    test "GETs /_data_stream/_stats for all streams" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.data_streams_stats(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_data_stream/_stats"
    end

    test "puts the name before _stats" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.data_streams_stats(name: "logs", context: context(port))
      assert Task.await(server).path == "/_data_stream/logs/_stats"
    end
  end

  describe "modify/2" do
    test "POSTs /_data_stream/_modify with the actions wrapped" do
      {port, server} = start_server()

      actions = [
        %{"add_backing_index" => %{"data_stream" => "logs", "index" => ".ds-logs-000001"}}
      ]

      assert {:ok, _} = DataStream.modify(actions, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_data_stream/_modify"
      assert req.body =~ ~s("actions":[)
      assert req.body =~ ~s("add_backing_index")
    end

    test "keeps the order of the actions, so a remove/add swap stays atomic" do
      {port, server} = start_server()

      actions = [
        %{"remove_backing_index" => %{"data_stream" => "a", "index" => "i"}},
        %{"add_backing_index" => %{"data_stream" => "b", "index" => "i"}}
      ]

      assert {:ok, _} = DataStream.modify(actions, context: context(port))

      body = Task.await(server).body

      assert :binary.match(body, "remove_backing_index") <
               :binary.match(body, "add_backing_index")
    end

    test "accepts an empty action list" do
      {port, server} = start_server()

      assert {:ok, _} = DataStream.modify([], context: context(port))
      assert Task.await(server).body == ~s({"actions":[]})
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
