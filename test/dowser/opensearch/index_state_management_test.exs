defmodule Dowser.Opensearch.IndexStateManagementTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub
  alias Dowser.Opensearch.IndexStateManagement, as: ISM

  @policy ~s({"_id":"logs","_seq_no":7,"_primary_term":1,"policy":{"default_state":"hot"}})
  @policy_response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@policy)}\r\n\r\n" <>
                     @policy

  @flat_error ~s({"error":"Policy not found"})
  @flat_error_response "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@flat_error)}\r\n\r\n" <>
                         @flat_error

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "put_policy/3" do
    test "PUTs /_plugins/_ism/policies/{policy_id}" do
      {port, server} = start_server()

      policy = %{"policy" => %{"default_state" => "hot"}}
      assert {:ok, _} = ISM.put_policy(policy, "logs", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_plugins/_ism/policies/logs"
      assert req.body == ~s({"policy":{"default_state":"hot"}})
    end

    test "forwards the optimistic-concurrency params an update needs" do
      {port, server} = start_server()

      assert {:ok, _} =
               ISM.put_policy(%{}, "logs",
                 params: [if_seq_no: 7, if_primary_term: 1],
                 context: context(port)
               )

      assert Task.await(server).path ==
               "/_plugins/_ism/policies/logs?if_seq_no=7&if_primary_term=1"
    end

    test "requires a policy_id, naming it in the error" do
      assert {:error, %ArgumentError{} = error} = ISM.put_policy(%{}, nil)
      assert Exception.message(error) =~ "policy_id is required"
    end
  end

  describe "get_policy/2 and get_policies/1" do
    test "get_policy/2 GETs the policy with its version" do
      {port, server} = start_server(@policy_response)

      assert {:ok, body} = ISM.get_policy("logs", context: context(port))
      assert body["_seq_no"] == 7
      assert body["_primary_term"] == 1

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_plugins/_ism/policies/logs"
    end

    test "get_policies/1 GETs the collection" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.get_policies(params: [size: 50], context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_plugins/_ism/policies?size=50"
    end
  end

  describe "put_policies/2 and delete_policy/2" do
    test "put_policies/2 PUTs the collection path" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.put_policies(%{"policies" => []}, context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_plugins/_ism/policies"
    end

    test "delete_policy/2 DELETEs the policy" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.delete_policy("logs", context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_plugins/_ism/policies/logs"
    end
  end

  describe "policy_exists/2" do
    test "HEADs the policy and maps 200 to true" do
      {port, server} = start_server(HTTPStub.head_response(200))

      assert ISM.policy_exists("logs", context: context(port)) == {:ok, true}

      req = Task.await(server)
      assert req.method == "HEAD"
      assert req.path == "/_plugins/_ism/policies/logs"
    end

    test "maps 404 to false" do
      {port, server} = start_server(HTTPStub.head_response(404))

      assert ISM.policy_exists("missing", context: context(port)) == {:ok, false}

      Task.await(server)
    end

    test "policy_exists?/2 raises on a genuine error" do
      {port, server} = start_server(@server_error_response)

      assert_raise Error, fn -> ISM.policy_exists?("logs", context: context(port)) end

      Task.await(server)
    end
  end

  describe "managing indices" do
    test "add_policy/2 POSTs /_plugins/_ism/add with the index appended" do
      {port, server} = start_server()

      assert {:ok, _} =
               ISM.add_policy(%{"policy_id" => "logs"},
                 index: "logs-000001",
                 context: context(port)
               )

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_plugins/_ism/add/logs-000001"
      assert req.body == ~s({"policy_id":"logs"})
    end

    test "add_policy/2 omits the index when absent" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.add_policy(%{}, context: context(port))
      assert Task.await(server).path == "/_plugins/_ism/add"
    end

    test "remove_policy/1 POSTs with no body" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.remove_policy(index: "logs-000001", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_plugins/_ism/remove/logs-000001"
      assert req.body == ""
    end

    test "change_policy/2 POSTs the new policy" do
      {port, server} = start_server()

      body = %{"policy_id" => "v2", "state" => "hot"}
      assert {:ok, _} = ISM.change_policy(body, index: "logs-*", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_plugins/_ism/change_policy/logs-*"
    end

    test "retry_index/2 POSTs the state to retry from" do
      {port, server} = start_server()

      assert {:ok, _} =
               ISM.retry_index(%{"state" => "warm"}, index: "logs-000001", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_plugins/_ism/retry/logs-000001"
      assert req.body == ~s({"state":"warm"})
    end

    test "retry_index/2 accepts an empty body to retry the failed action" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.retry_index(%{}, context: context(port))

      req = Task.await(server)
      assert req.path == "/_plugins/_ism/retry"
      assert req.body == "{}"
    end

    test "explain_policy/1 GETs /_plugins/_ism/explain" do
      {port, server} = start_server()

      assert {:ok, _} =
               ISM.explain_policy(
                 index: "logs-000001",
                 params: [show_policy: true],
                 context: context(port)
               )

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_plugins/_ism/explain/logs-000001?show_policy=true"
    end

    test "joins several indices with commas" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.explain_policy(index: ["a", "b"], context: context(port))
      assert Task.await(server).path == "/_plugins/_ism/explain/a,b"
    end
  end

  describe "refresh_search_analyzers/2" do
    test "POSTs /_plugins/_refresh_search_analyzers/{index}, outside the _ism prefix" do
      {port, server} = start_server()

      assert {:ok, _} = ISM.refresh_search_analyzers("posts", context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_plugins/_refresh_search_analyzers/posts"
    end

    test "requires an index" do
      assert {:error, %ArgumentError{} = error} = ISM.refresh_search_analyzers(nil)
      assert Exception.message(error) =~ "index is required"
    end
  end

  describe "ISM's flat error bodies" do
    test "a plain string error lands in :reason with no :type" do
      {port, server} = start_server(@flat_error_response)

      assert {:error, %Error{status: 404, type: nil, reason: "Policy not found"}} =
               ISM.get_policy("missing", context: context(port))

      Task.await(server)
    end

    test "the bang variant raises it with the message readable" do
      {port, server} = start_server(@flat_error_response)

      assert_raise Error, ~r/HTTP 404: Policy not found/, fn ->
        ISM.get_policy!("missing", context: context(port))
      end

      Task.await(server)
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
