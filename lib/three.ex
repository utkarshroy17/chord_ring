# TODO: Find fingers for last node
# TODO: Verify if fingers are correct

defmodule Chord do
  use GenServer

  @max_hashcode "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
  def max_hashcode, do: @max_hashcode

  def max_hashcode_integer do
    {int, _} = @max_hashcode |> Integer.parse(16)
    int
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def create_nodes(server, num_nodes, num_requests) do
    GenServer.cast(server, {:create_nodes, {num_nodes, num_requests}})
  end

  def converge(server, average_hops) do
    GenServer.cast(server, {:converge, {average_hops}})
  end

  def init(:ok) do
    {:ok,
     %{
       :chord_ring => nil,
       :hash_map => nil,
       :num_nodes => 0,
       :num_converged_nodes => 0,
       :cummulative_average_hops => 0
     }}
  end

  @doc """
   hash_map = %{pid1 => hashcode1}
   chord_ring = %{pid1 => {predecessor_hashcode, predecessor_pid, successor_hashcode, successor_pid}}
   sorted_hash_list = [pidX: hashcodeX, pidY: hashcodeY]
  """

  def handle_create_nodes(num_nodes, num_requests, state) do
    IO.puts("Creating chord...")
    hash_map = createNodes(num_nodes, num_requests)
    sorted_hash_list = hash_map |> Enum.sort_by(&elem(&1, 1))
    chord_ring = createRing(hash_map)

    Enum.map(hash_map, fn {pid, hashcode} ->
      neighbors = Map.get(chord_ring, Map.get(hash_map, pid))
      successor = %{:pid => elem(neighbors, 3), :hashcode => elem(neighbors, 2)}
      predecessor = %{:pid => elem(neighbors, 1), :hashcode => elem(neighbors, 0)}
      {hashcode_integer, _} = hashcode |> Integer.parse(16)

      set_finger = fn i ->
        two_power_i = :math.pow(2, i) |> Kernel.trunc()
        sum_modulo = (hashcode_integer + two_power_i) |> rem(max_hashcode_integer())
        new_hashcode = sum_modulo |> Integer.to_string(16) |> String.pad_leading(40, "0")

        Enum.find(sorted_hash_list, fn {_pid, hashcode} -> hashcode > new_hashcode end) ||
          hd(sorted_hash_list)
      end

      fingers = Enum.map(1..159, set_finger)
      Participant.set_info(pid, hashcode, predecessor, successor, fingers)
    end)

    #Inspect all nodes
    hash_map
    |> Map.keys()
    |> Enum.map(fn pid ->
      IO.inspect(pid); IO.puts("has started requesting");
      Participant.start_requesting(pid)
      # Participant.inspect(pid) |> IO.inspect(limit: :infinity)
    end)

    new_state = put_in(state.chord_ring, chord_ring)
    put_in(new_state.num_nodes, num_nodes)
  end

  def handle_converge(average_hops, state) do
    state =
      Map.merge(state, %{
        :cummulative_average_hops => state.cummulative_average_hops + average_hops,
        :num_converged_nodes => state.num_converged_nodes + 1
      })

    if state.num_converged_nodes == state.num_nodes do
      IO.puts("Average hops across all nodes in chord #{state.cummulative_average_hops / state.num_nodes}")
      Process.exit(self(), "All nodes have converged")
    end

    state
  end

  def handle_cast({method, methodArgs}, state) do
    case method do
      :create_nodes ->
        {num_nodes, num_requests} = methodArgs
        new_state = handle_create_nodes(num_nodes, num_requests, state)
        {:noreply, new_state}

      :converge ->
        {average_hops} = methodArgs
        new_state = handle_converge(average_hops, state)
        {:noreply, new_state}
    end
  end

  def createNodes(num_nodes, num_requests) do
    1..num_nodes |> Enum.map(fn _index -> Participant.start_link(num_requests) end) |> Map.new()
  end

  def createRing(hash_map) do
    hash_list = Map.values(hash_map) |> Enum.sort()

    successor_map =
      for a <- hash_list, id = a, data = get_successor(hash_list, a, hash_map), into: %{} do
        {id, data}
      end

    predecessor_map =
      for a <- hash_list, id = a, data = get_predecessor(hash_list, a, hash_map), into: %{} do
        {id, data}
      end

    _pre_suc_map =
      Map.merge(predecessor_map, successor_map, fn _k, v1, v2 ->
        List.to_tuple(Tuple.to_list(v1) ++ Tuple.to_list(v2))
      end)
  end

  def get_successor(hash_list, node_hash, hash_map) do
    cond do
      node_hash == List.last(hash_list) ->
        {List.first(hash_list), get_key(hash_map, List.first(hash_list))}

      hd(hash_list) == node_hash ->
        {List.first(tl(hash_list)), get_key(hash_map, List.first(tl(hash_list)))}

      true ->
        get_successor(tl(hash_list), node_hash, hash_map)
    end
  end

  def get_predecessor(hash_list, node_hash, hash_map) do
    cond do
      node_hash == List.first(hash_list) ->
        {List.last(hash_list), get_key(hash_map, List.last(hash_list))}

      List.first(tl(hash_list)) == node_hash ->
        {hd(hash_list), get_key(hash_map, hd(hash_list))}

      true ->
        get_predecessor(tl(hash_list), node_hash, hash_map)
    end
  end

  def get_key(hash_map, val) do
    hash_map |> Enum.find(fn {_k, v} -> v == val end) |> elem(0)
  end
end

defmodule Three do
  def start(num_nodes \\ 100, num_requests \\ 10) do
    {:ok, pid} = Chord.start_link([])
    Process.register(pid, :main)
    Chord.create_nodes(:main, num_nodes, num_requests)
    # Chord.join_nodes(num_nodes)
  end
end

# # Hashcode modulo
# a = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
# {a1, _} = a |> Integer.parse(16)
# #a1 = 115792089237316195423570985008687907853269984665640564039457584007913129639935,
# b = "10000000000000000000000000000000000000000000000000000000000000000"
# {b1, _} = b |> Integer.parse(16)
# # b1 = 115792089237316195423570985008687907853269984665640564039457584007913129639936,
# c1 = rem(b1,a1)
# c1 |> Integer.to_string(16) |> String.pad_leading(64,"0")
