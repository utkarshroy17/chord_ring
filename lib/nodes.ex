# TODO: handle predecessor, successor = nil
defmodule Participant do
  use GenServer

  @max_hashcode "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
  def max_hashcode, do: @max_hashcode

  def max_hashcode_integer do
    {int, _} = @max_hashcode |> Integer.parse(16)
    int
  end

  def start_link(num_requests) do
    {:ok, pid} = GenServer.start_link(__MODULE__, num_requests, [])
    hashcode = :crypto.hash(:sha, Kernel.inspect(pid)) |> Base.encode16()
    set_hashcode(pid, hashcode)
    {pid, hashcode}
  end

  def inspect(server) do
    GenServer.call(server, {:inspect})
  end

  # Set hashcode, predecessor and successor. Used to hardcode initial chord config
  def set_info(node, hashcode, predecessor, successor, fingers) do
    GenServer.cast(node, {:set_info, {hashcode, predecessor, successor, fingers}})
  end

  def set_hashcode(server, hashcode) do
    GenServer.cast(server, {:set_hashcode, {hashcode}})
  end

  def start_requesting(server) do
    GenServer.cast(server, {:start_requesting, {}})
  end

  def stabilize(server, hashcode) do
    GenServer.cast(server, {:stabilize, {hashcode}})
  end

  def get_successor(server) do
    GenServer.call(server, {:get_successor})
  end

  def create(server) do
    GenServer.cast(server, {:create, {}})
  end

  def notify(server, hashcode) do
    GenServer.cast(server, {:notify, {hashcode}})
  end

  # argument_map = %{id!, request_id, successor, route_stack, num_hops}
  def find_successor(server, argument_map) do
    GenServer.cast(server, {:find_successor, {argument_map}})
  end

  # argument_map = %{id!, request_id, successor, route_stack, num_hops}
  def reply_find_successor(server, argument_map) do
    GenServer.cast(server, {:reply_find_successor, {argument_map}})
  end

  # Server callbacks
  def closest_preceding_node(id, state) do
    fingers_reverse = Enum.reverse(state.fingers)
    # IO.puts("c_p_n #{id}")
    # IO.inspect(state.hashcode)

    {pid, _hashcode} =
      fingers_reverse
      |> Enum.find(fn {_, finger_hashcode} ->
        if state.hashcode < id do
          state.hashcode < finger_hashcode and finger_hashcode < id
        else
          (state.hashcode < finger_hashcode and finger_hashcode < max_hashcode()) or
            ("0" < finger_hashcode and finger_hashcode < id)
        end
      end)

    pid || self()
  end

  # argument_map = %{id!, request_id, successor, route_stack, num_hops}
  def handle_find_successor(argument_map, state) do
    isSourceNode? = Map.get(argument_map, :request_id) == nil

    {temp_argument_map, temp_state} =
      if isSourceNode? == true do
        request_id = System.unique_integer()

        {
          %{
            :request_id => request_id,
            :successor => nil,
            :route_stack => Stack.new() |> Stack.push(self()),
            :num_hops => 0
          },
          %{
            :pending_requests => [request_id | state.pending_requests]
          }
        }
      else
        {
          %{
            :route_stack => argument_map.route_stack |> Stack.push(self()),
            :num_hops => argument_map.num_hops + 1
          },
          state
        }
      end

    argument_map = Map.merge(argument_map, temp_argument_map)
    state = Map.merge(state, temp_state)

    maxHashcode = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
    # If the successor is not beyond the end of the circle
    # If the successor is after the end of the circle
    isKeyWithinSuccessor? =
      if state.hashcode < state.successor.hashcode do
        state.hashcode < argument_map.id and argument_map.id <= state.successor.hashcode
      else
        (state.hashcode < argument_map.id and argument_map.id < maxHashcode) or
          ("0" < argument_map.id and argument_map.id <= state.successor.hashcode)
      end

    if isKeyWithinSuccessor? do
      argument_map = put_in(argument_map.successor, state.successor)
      {next_hop, updated_route_stack} = Stack.pop(argument_map.route_stack)
      argument_map = put_in(argument_map.route_stack, updated_route_stack)
      Participant.reply_find_successor(next_hop, argument_map)
    else
      # n1 should be pid and not {pid, hashcode}
      n1 = closest_preceding_node(argument_map.id, state)
      Participant.find_successor(n1, argument_map)
    end

    state
  end

  def handle_reply_find_successor(argument_map, state) do
    # The reply has come back to the source
    isRouteStackEmpty? = length(argument_map.route_stack) == 0

    temp_state =
      if isRouteStackEmpty? == true do
        state =
          update_in(state.pending_requests, fn pending_requests ->
            List.delete(pending_requests, argument_map.request_id)
          end)
        state = put_in(state.completed_requests[argument_map.request_id], %{
          :num_hops => argument_map.num_hops,
          :successor => argument_map.successor
        })
        # IO.puts("reply received"); IO.inspect(state.completed_requests)
        state
      else
        {next_hop, updated_route_stack} = Stack.pop(argument_map.route_stack)
        argument_map = put_in(argument_map.route_stack, updated_route_stack)
        Participant.reply_find_successor(next_hop, argument_map)
        state
      end

    Map.merge(state, temp_state)
  end

  def handle_start_requesting do
    Process.send_after(self(), :perform_request, 1000)
  end

  @doc """
    Participant state so far = %{
      :hashcode,
      :successor => %{:pid, :hashcode},
      :predecessor => %{:pid, :hashcode}
      :num_requests,
      :pending_requests => [request_id1, request_id2],
      :completed_requests => %{
        request_id1: %{:num_hops => argument_map.num_hops, :successor => argument_map.successor}
      },
      :fingers,
      :converged?
    }
  """
  def init(num_requests) do
    {:ok,
     %{
       :hashcode => nil,
       :successor => nil,
       :predecessor => nil,
       :num_requests => num_requests,
       :pending_requests => [],
       :completed_requests => %{},
       :fingers => nil,
       :converged? => false
     }}
  end

  def handle_cast({method, methodArgs}, state) do
    case method do
      :set_hashcode ->
        {hashcode} = methodArgs
        {:noreply, Map.merge(state, %{:hashcode => hashcode})}

      :set_info ->
        {hashcode, predecessor, successor, fingers} = methodArgs

        {:noreply,
         Map.merge(state, %{
           :hashcode => hashcode,
           :predecessor => predecessor,
           :successor => successor,
           :fingers => fingers
         })}

      :create ->
        {:noreply,
         Map.merge(state, %{
           :predecessor => nil,
           :successor => %{:pid => self(), :hashcode => state.hashcode}
         })}

      :find_successor ->
        {argument_map} = methodArgs
        state = handle_find_successor(argument_map, state)
        {:noreply, state}

      :reply_find_successor ->
        {argument_map} = methodArgs
        state = handle_reply_find_successor(argument_map, state)
        {:noreply, state}

      :start_requesting ->
        handle_start_requesting()
        {:noreply, state}

      :stabilize ->
        stabilize_node()
        {:noreply, state}

      :notify ->
        {hashcode} = methodArgs
        if state.predecessor == nil or (state.predecessor < hashcode and hashcode < state.hashcode) do
          put_in state.predecessor, hashcode
        end
        {:noreply, state}
    end
  end

  def handle_call({method}, _from, state) do
    case method do
      :inspect ->
        {:reply, state, state}
      :get_successor ->
        {:reply, state.predecessor.hashcode, state}
    end

  end

  # TODO: Test start_requesting and converge!
  def handle_perform_request(state) do
    _new_state =
      cond do
        Map.size(state.completed_requests) < state.num_requests ->
          random_string = :crypto.strong_rand_bytes(16)
          random_key = :crypto.hash(:sha, random_string) |> Base.encode16()
          find_successor(self(), %{:id => random_key})
          Process.send_after(self(), :perform_request, 1000)
          state

        state.converged? == false ->
          total_hops =
            Enum.reduce(state.completed_requests, 0, fn {_, result_map}, acc ->
              acc + result_map.num_hops
            end)
          average_hops = total_hops/state.num_requests
          IO.inspect(self()); IO.puts("Node has converged with average hops = #{average_hops}")
          Chord.converge(:main, average_hops)
          put_in(state.converged?, true)
      end
  end

  defp stabilize_node() do
    Process.send_after(self(), :stabilize, 1 * 1000)
  end

  def handle_stabilize(state) do
    successor_pid = Map.get(state.successor, :pid)
    successor_predecessor = get_successor(successor_pid)
    if successor_predecessor > state.hashcode and successor_predecessor < state.successor do
      put_in state.successor, successor_predecessor
    end
    notify(successor_pid, state.hashcode)
    state
  end

  def handle_info(method, state) do
    case method do
      :perform_request ->
        state = handle_perform_request(state)
        {:noreply, state}

      :stabilize ->
        state = handle_stabilize(state)
        stabilize_node()
        {:noreply, state}
    end
  end
end
