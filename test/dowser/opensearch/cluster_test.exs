defmodule Dowser.Opensearch.ClusterTest do
  use ExUnit.Case, async: false

  alias Dowser.Opensearch.Cluster
  alias Dowser.Opensearch.Error
  alias Dowser.Opensearch.HTTPStub

  @health ~s({"cluster_name":"opensearch","status":"green","number_of_nodes":3})
  @health_response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@health)}\r\n\r\n" <>
                     @health

  @server_error ~s({"message":"boom"})
  @server_error_response "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(@server_error)}\r\n\r\n" <>
                           @server_error

  describe "health/1" do
    test "GETs /_cluster/health and decodes the response" do
      {port, server} = start_server(@health_response)

      assert {:ok, body} = Cluster.health(context: context(port))
      assert body["status"] == "green"

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_cluster/health"
    end

    test "appends an index target" do
      {port, server} = start_server(@health_response)

      assert {:ok, _} = Cluster.health(index: "posts", context: context(port))
      assert Task.await(server).path == "/_cluster/health/posts"
    end

    test "forwards wait_for_status" do
      {port, server} = start_server(@health_response)

      assert {:ok, _} =
               Cluster.health(
                 params: [wait_for_status: "yellow", timeout: "30s"],
                 context: context(port)
               )

      assert Task.await(server).path == "/_cluster/health?wait_for_status=yellow&timeout=30s"
    end

    test "wraps a non-2xx response in a Dowser.Opensearch.Error" do
      {port, server} = start_server(@server_error_response)

      assert {:error, %Error{status: 500}} = Cluster.health(context: context(port))

      Task.await(server)
    end
  end

  describe "state/1" do
    test "GETs /_cluster/state with no metric" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.state(context: context(port))
      assert Task.await(server).path == "/_cluster/state"
    end

    test "appends a metric" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.state(metric: "metadata", context: context(port))
      assert Task.await(server).path == "/_cluster/state/metadata"
    end

    test "appends an index after the metric" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.state(metric: "metadata", index: "posts", context: context(port))
      assert Task.await(server).path == "/_cluster/state/metadata/posts"
    end

    test "refuses an index with no metric rather than building a wrong path" do
      assert {:error, %ArgumentError{} = error} = Cluster.state(index: "posts")
      assert Exception.message(error) =~ ":index needs :metric"
    end

    test "joins several metrics with commas" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.state(metric: ["metadata", "nodes"], context: context(port))
      assert Task.await(server).path == "/_cluster/state/metadata,nodes"
    end
  end

  describe "stats/1" do
    test "GETs /_cluster/stats" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.stats(context: context(port))
      assert Task.await(server).path == "/_cluster/stats"
    end

    test "inserts /nodes before the node id" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.stats(node_id: "node-1", context: context(port))
      assert Task.await(server).path == "/_cluster/stats/nodes/node-1"
    end
  end

  describe "settings" do
    test "get_settings/1 GETs /_cluster/settings" do
      {port, server} = start_server()

      assert {:ok, _} =
               Cluster.get_settings(params: [include_defaults: true], context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_cluster/settings?include_defaults=true"
    end

    test "put_settings/2 PUTs the body" do
      {port, server} = start_server()

      settings = %{"persistent" => %{"cluster.routing.allocation.enable" => "all"}}
      assert {:ok, _} = Cluster.put_settings(settings, context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_cluster/settings"
      assert req.body =~ ~s("persistent")
    end

    test "put_settings/2 sends a nil value, which resets a setting" do
      {port, server} = start_server()

      assert {:ok, _} =
               Cluster.put_settings(%{"transient" => %{"x" => nil}}, context: context(port))

      assert Task.await(server).body == ~s({"transient":{"x":null}})
    end
  end

  describe "routing" do
    test "reroute/2 POSTs /_cluster/reroute" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.reroute(%{"commands" => []}, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_cluster/reroute"
    end

    test "reroute/2 forwards dry_run" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.reroute(%{}, params: [dry_run: true], context: context(port))
      assert Task.await(server).path == "/_cluster/reroute?dry_run=true"
    end

    test "allocation_explain/2 POSTs /_cluster/allocation/explain" do
      {port, server} = start_server()

      body = %{"index" => "posts", "shard" => 0, "primary" => true}
      assert {:ok, _} = Cluster.allocation_explain(body, context: context(port))

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_cluster/allocation/explain"
    end
  end

  describe "voting configuration exclusions" do
    test "post_voting_config_exclusions/1 POSTs with the node names as params" do
      {port, server} = start_server()

      assert {:ok, _} =
               Cluster.post_voting_config_exclusions(
                 params: [node_names: "node-1"],
                 context: context(port)
               )

      req = Task.await(server)
      assert req.method == "POST"
      assert req.path == "/_cluster/voting_config_exclusions?node_names=node-1"
    end

    test "delete_voting_config_exclusions/1 DELETEs the same path" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.delete_voting_config_exclusions(context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_cluster/voting_config_exclusions"
    end
  end

  describe "weighted routing" do
    test "put_weighted_routing/3 PUTs the weights for an attribute" do
      {port, server} = start_server()

      body = %{"weights" => %{"us-east-1a" => "1", "us-east-1b" => "0"}}
      assert {:ok, _} = Cluster.put_weighted_routing(body, "zone", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_cluster/routing/awareness/zone/weights"
    end

    test "get_weighted_routing/2 GETs the weights" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.get_weighted_routing("zone", context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_cluster/routing/awareness/zone/weights"
    end

    test "both require an attribute, naming it in the error" do
      assert {:error, %ArgumentError{} = error} = Cluster.put_weighted_routing(%{}, nil)
      assert Exception.message(error) =~ "attribute is required"

      assert {:error, %ArgumentError{}} = Cluster.get_weighted_routing(nil)
    end

    test "delete_weighted_routing/1 DELETEs the unscoped path" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.delete_weighted_routing(context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_cluster/routing/awareness/weights"
    end
  end

  describe "decommission awareness" do
    test "put_decommission_awareness/3 PUTs the attribute and value" do
      {port, server} = start_server()

      assert {:ok, _} =
               Cluster.put_decommission_awareness("zone", "us-east-1c", context: context(port))

      req = Task.await(server)
      assert req.method == "PUT"
      assert req.path == "/_cluster/decommission/awareness/zone/us-east-1c"
    end

    test "get_decommission_awareness/2 GETs the _status path" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.get_decommission_awareness("zone", context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_cluster/decommission/awareness/zone/_status"
    end

    test "put_decommission_awareness/3 names whichever argument is missing" do
      assert {:error, %ArgumentError{} = error} = Cluster.put_decommission_awareness(nil, "a")
      assert Exception.message(error) =~ "awareness_attribute_name is required"

      assert {:error, %ArgumentError{} = error} = Cluster.put_decommission_awareness("zone", nil)
      assert Exception.message(error) =~ "awareness_attribute_value is required"
    end

    test "delete_decommission_awareness/1 DELETEs the unscoped path" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.delete_decommission_awareness(context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/_cluster/decommission/awareness"
    end
  end

  describe "pending_tasks/1 and remote_info/1" do
    test "pending_tasks/1 GETs /_cluster/pending_tasks" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.pending_tasks(context: context(port))
      assert Task.await(server).path == "/_cluster/pending_tasks"
    end

    test "remote_info/1 GETs /_remote/info, outside the /_cluster prefix" do
      {port, server} = start_server()

      assert {:ok, _} = Cluster.remote_info(context: context(port))

      req = Task.await(server)
      assert req.method == "GET"
      assert req.path == "/_remote/info"
    end
  end

  defp context(port), do: HTTPStub.context(port)

  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)
end
