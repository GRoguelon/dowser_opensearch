defmodule Dowser.Opensearch.RepositoryTest do
  use ExUnit.Case, async: true

  alias Dowser.Opensearch.HTTPStub

  defp context(port), do: HTTPStub.context(port)
  defp start_server(response \\ HTTPStub.ok_response()), do: HTTPStub.start_server(response)

  defmodule StaticRepo do
    use Dowser.Opensearch.Repository,
      index: "probes",
      only: [
        search: [:search],
        document: [:get, :exists, :index],
        index: [:refresh, :delete_index],
        mappings: [:get_mapping],
        cat: [:indices],
        list: [:indices],
        ism: [:explain_policy]
      ]
  end

  defmodule DynamicRepo do
    use Dowser.Opensearch.Repository,
      only: [search: [:msearch, :search], document: [:get]],
      index: &index_name/1

    def index_name(term) do
      "my_index_#{term}"
    end
  end

  defmodule ExceptRepo do
    use Dowser.Opensearch.Repository,
      index: :probes,
      except: [:document, :index, :cat, :list, :ism, search: [:msearch]]
  end

  describe "static index" do
    test "search/2 injects the index option" do
      {port, server} = start_server()

      assert {:ok, _} = StaticRepo.search(%{}, context: context(port))
      assert Task.await(server).path == "/probes/_search"
    end

    test "search/2 overwrites a caller-supplied index" do
      {port, server} = start_server()

      assert {:ok, _} = StaticRepo.search(%{}, index: "other", context: context(port))
      assert Task.await(server).path == "/probes/_search"
    end

    test "positional index arguments disappear" do
      {port, server} = start_server()

      assert {:ok, _} = StaticRepo.get_doc("1", context: context(port))
      assert Task.await(server).path == "/probes/_doc/1"

      {port, server} = start_server()

      assert {:ok, _} = StaticRepo.index_doc(%{"title" => "hi"}, context: context(port))
      assert Task.await(server).path == "/probes/_doc"

      {port, server} = start_server()

      assert {:ok, _} = StaticRepo.delete_index(context: context(port))

      req = Task.await(server)
      assert req.method == "DELETE"
      assert req.path == "/probes"
    end

    test "opts-style index functions target the repository index" do
      {port, server} = start_server()

      assert {:ok, _} = StaticRepo.refresh(context: context(port))
      assert Task.await(server).path == "/probes/_refresh"
    end

    test "bang and predicate variants are generated" do
      {port, server} = start_server()
      assert %{"acknowledged" => true} = StaticRepo.search!(%{}, context: context(port))
      Task.await(server)

      {port, server} = start_server(HTTPStub.head_response(404))
      assert {:ok, false} = StaticRepo.doc_exists("1", context: context(port))
      Task.await(server)

      {port, server} = start_server(HTTPStub.head_response(200))
      assert StaticRepo.doc_exists?("1", context: context(port)) == true
      Task.await(server)
    end

    test "functions from the OpenSearch-specific modules are bound too" do
      {port, server} = start_server()
      assert {:ok, _} = StaticRepo.get_mapping(context: context(port))
      assert Task.await(server).path == "/probes/_mapping"

      {port, server} = start_server()
      assert {:ok, _} = StaticRepo.explain_policy(context: context(port))
      assert Task.await(server).path == "/_plugins/_ism/explain/probes"
    end

    test "unselected functions are not generated" do
      refute function_exported?(StaticRepo, :msearch, 2)
      refute function_exported?(StaticRepo, :count, 2)
      refute function_exported?(StaticRepo, :delete_doc, 2)
    end
  end

  describe "renamed functions" do
    test "the cat and list namesakes are prefixed rather than clashing" do
      {port, server} = start_server()
      assert {:ok, _} = StaticRepo.cat_indices(context: context(port))
      assert Task.await(server).path == "/_cat/indices/probes"

      {port, server} = start_server()
      assert {:ok, _} = StaticRepo.list_indices(context: context(port))
      assert Task.await(server).path == "/_list/indices/probes"
    end

    test "neither is reachable under its bare name" do
      refute function_exported?(StaticRepo, :indices, 1)
    end

    test "the bang variants follow the rename" do
      {port, server} = start_server()
      assert %{"acknowledged" => true} = StaticRepo.cat_indices!(context: context(port))
      Task.await(server)
    end
  end

  describe "dynamic index" do
    test "the :index option is the term passed to the index function" do
      {port, server} = start_server()

      assert {:ok, _} = DynamicRepo.search(%{}, index: "day1", context: context(port))
      assert Task.await(server).path == "/my_index_day1/_search"
    end

    test "positional index arguments become terms" do
      {port, server} = start_server()

      assert {:ok, _} = DynamicRepo.get_doc("day1", "1", context: context(port))
      assert Task.await(server).path == "/my_index_day1/_doc/1"
    end

    test "an absent :index option passes nil to the index function" do
      {port, server} = start_server()

      assert {:ok, _} = DynamicRepo.search(%{}, context: context(port))
      assert Task.await(server).path == "/my_index_/_search"
    end
  end

  describe "except" do
    test "keeps everything but the excluded functions" do
      {port, server} = start_server()

      assert {:ok, _} = ExceptRepo.count(%{}, context: context(port))
      assert Task.await(server).path == "/probes/_count"

      refute function_exported?(ExceptRepo, :msearch, 2)
      refute function_exported?(ExceptRepo, :get, 2)
      refute function_exported?(ExceptRepo, :refresh, 1)
      refute function_exported?(ExceptRepo, :cat_indices, 1)
    end

    test "keeps the modules it did not exclude" do
      {port, server} = start_server()

      assert {:ok, _} = ExceptRepo.get_settings(context: context(port))
      assert Task.await(server).path == "/probes/_settings"
    end
  end

  describe "cross-module name collisions" do
    test "no two API modules expose a repository function under the same generated name" do
      modules = [
        Dowser.Opensearch.Alias,
        Dowser.Opensearch.Cat,
        Dowser.Opensearch.Document,
        Dowser.Opensearch.Index,
        Dowser.Opensearch.IndexSettings,
        Dowser.Opensearch.IndexStateManagement,
        Dowser.Opensearch.List,
        Dowser.Opensearch.Mappings,
        Dowser.Opensearch.Reindex,
        Dowser.Opensearch.Search
      ]

      # Every name a repository would generate, after `renames/0` is applied —
      # which is what `use` refuses to compile a duplicate of. Building the
      # repository below is the check: it raises at compile time on a clash
      # `renames/0` does not cover.
      assert Enum.all?(modules, &function_exported?(&1, :__repository__, 0))

      defmodule EveryFunction do
        use Dowser.Opensearch.Repository, index: "probes"
      end

      assert function_exported?(EveryFunction, :search, 2)
      assert function_exported?(EveryFunction, :cat_indices, 1)
      assert function_exported?(EveryFunction, :list_indices, 1)
    end
  end

  describe "compile-time validation" do
    test "requires the :index option" do
      assert_raise ArgumentError, ~r/:index option is required/, fn ->
        defmodule NoIndex do
          use Dowser.Opensearch.Repository, only: [:search]
        end
      end
    end

    test "rejects unknown function names" do
      assert_raise ArgumentError, ~r/unknown repository function :nope/, fn ->
        defmodule UnknownFunction do
          use Dowser.Opensearch.Repository, index: "x", only: [search: [:nope]]
        end
      end
    end

    test "rejects unknown module keys" do
      assert_raise ArgumentError, ~r/unknown module key :cluster/, fn ->
        defmodule UnknownModule do
          use Dowser.Opensearch.Repository, index: "x", only: [:cluster]
        end
      end
    end

    test "rejects :only combined with :except" do
      assert_raise ArgumentError, ~r/mutually exclusive/, fn ->
        defmodule Both do
          use Dowser.Opensearch.Repository, index: "x", only: [:search], except: [:document]
        end
      end
    end

    test "rejects an invalid :index" do
      assert_raise ArgumentError, ~r/:index must be/, fn ->
        defmodule BadIndex do
          use Dowser.Opensearch.Repository, index: 123, only: [:search]
        end
      end
    end
  end
end
