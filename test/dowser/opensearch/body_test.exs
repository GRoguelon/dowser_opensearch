defmodule Dowser.Opensearch.BodyTest do
  use ExUnit.Case, async: true

  alias Dowser.Opensearch.Body

  describe "value/3" do
    test "reads a string key" do
      assert Body.value(%{"acknowledged" => true}, "acknowledged") == true
    end

    test "reads an atom key under the same name" do
      assert Body.value(%{acknowledged: true}, "acknowledged") == true
    end

    test "returns the default when the name is absent" do
      assert Body.value(%{"other" => 1}, "acknowledged") == nil
      assert Body.value(%{"other" => 1}, "acknowledged", :missing) == :missing
    end

    test "returns the default for a value that is not a plain map" do
      assert Body.value("not a map", "acknowledged", :missing) == :missing
      assert Body.value(nil, "acknowledged", :missing) == :missing
      assert Body.value([%{"acknowledged" => true}], "acknowledged", :missing) == :missing
    end

    test "returns the default for a struct, which is not a response body" do
      assert Body.value(~D[2024-01-01], "year", :missing) == :missing
    end

    test "distinguishes a stored nil from an absent key" do
      assert Body.value(%{"result" => nil}, "result", :missing) == nil
    end
  end

  describe "first/2" do
    test "returns the first name the map holds, with its value" do
      assert Body.first(%{"index" => %{"_id" => "1"}}, ["index", "create", "delete"]) ==
               {"index", %{"_id" => "1"}}
    end

    test "honours the order of the names rather than the map's" do
      map = %{"delete" => %{"_id" => "2"}, "index" => %{"_id" => "1"}}

      assert Body.first(map, ["index", "delete"]) == {"index", %{"_id" => "1"}}
      assert Body.first(map, ["delete", "index"]) == {"delete", %{"_id" => "2"}}
    end

    test "matches an atom key under the same name" do
      assert Body.first(%{index: %{_id: "1"}}, ["index"]) == {"index", %{_id: "1"}}
    end

    test "finds a name whose stored value is nil" do
      assert Body.first(%{"index" => nil}, ["index"]) == {"index", nil}
    end

    test "returns nil when the map holds none of the names" do
      assert Body.first(%{"update" => %{}}, ["index", "create"]) == nil
    end

    test "returns nil for a value that is not a map" do
      assert Body.first("not a map", ["index"]) == nil
      assert Body.first(nil, ["index"]) == nil
    end
  end
end
