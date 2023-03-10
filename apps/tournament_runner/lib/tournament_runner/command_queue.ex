defmodule TournamentRunner.CommandQueue do
  use GenServer

  require Logger

  alias TournamentRunner.Queue
  alias TournamentRunner.Script

  @enforce_keys [:queue, :running?]
  defstruct [:queue, :running?]

  @name __MODULE__

  def queue_automation(driver) do
    GenServer.cast(@name, {:enqueue, {:run_automation, driver}})
  end

  def reset_amiibo_state() do
    GenServer.cast(@name, {:enqueue, :reset_amiibo_state})
  end

  def queue_function(fun) when is_function(fun, 0) do
    GenServer.cast(@name, {:enqueue, {:run_function, fun}})
  end

  def dequeue() do
    GenServer.call(@name, :dequeue)
  end

  def clear() do
    GenServer.cast(@name, :clear)
  end

  def current() do
    GenServer.call(@name, :current)
  end

  ## GenServer

  def init(_) do
    state = %__MODULE__{queue: Queue.new(), running?: false}
    {:ok, state}
  end

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {GenServer, :start_link, [__MODULE__, [:ok], [name: @name]]}
    }
  end

  def handle_cast({:enqueue, command}, state) do
    new_queue = Queue.push_back(state.queue, command)
    new_state = %__MODULE__{state | queue: new_queue}

    if state.running? do
      {:noreply, new_state}
    else
      new_state = %__MODULE__{new_state | running?: true}
      {:noreply, new_state, {:continue, :process_command}}
    end
  end

  def handle_cast(:clear, state) do
    new_state = %__MODULE__{state | queue: Queue.new()}
    {:noreply, new_state}
  end

  def handle_cast(:process_command, state) do
    {:noreply, state, {:continue, :process_command}}
  end

  def handle_call(:dequeue, _from, state) do
    {q, command} = Queue.pop_front(state.queue)
    new_state = %__MODULE__{state | queue: q}

    {:reply, command, new_state}
  end

  def handle_call(:current, _from, state) do
    list = Enum.to_list(state.queue)

    {:reply, list, state}
  end

  def handle_continue(:process_command, state) do
    if Queue.empty?(state.queue) do
      new_state = %__MODULE__{state | running?: false}
      {:noreply, new_state}
    else
      {q, command} = Queue.pop_front(state.queue)
      new_state = %__MODULE__{state | queue: q}

      case run_command(command) do
        :run_next ->
          {:noreply, new_state, {:continue, :process_command}}

        :wait ->
          {:noreply, new_state}
      end
    end
  end

  ## Helpers

  defp run_command({:run_automation, driver = %module{}}) do
    me = self()

    Task.start(fn ->
      module.run(driver)
      GenServer.cast(me, :process_command)
    end)

    :wait
  end

  defp run_command(:reset_amiibo_state) do
    me = self()

    # I could watch for the task to complete or timeout if needed.
    Task.start(fn ->
      Script.clear_amiibo_cache()
      GenServer.cast(me, :process_command)
    end)

    :wait
  end

  defp run_command({:run_function, fun}) do
    fun.()
    :run_next
  end
end
