defmodule BacksBacksBacks.TabOrganizer.Scheduler do
  @moduledoc """
  Lightweight in-memory scheduler for periodic tab organization.
  """

  use GenServer

  require Logger

  alias BacksBacksBacks.Accounts
  alias BacksBacksBacks.TabOrganizer
  alias BacksBacksBacksWeb.Presence

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick(0)
    {:ok, %{running: MapSet.new(), refs: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick(interval_ms())

    state =
      Accounts.list_users()
      |> Enum.filter(&online?/1)
      |> Enum.reduce(state, &start_user_task/2)

    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {user_id, state} = pop_ref(state, ref)

    case result do
      {:error, reason} ->
        Logger.warning("Tab organization failed for user #{user_id}: #{inspect(reason)}")

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {user_id, state} = pop_ref(state, ref)

    if reason != :normal do
      Logger.warning("Tab organization task crashed for user #{user_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp start_user_task(user, state) do
    if MapSet.member?(state.running, user.id) do
      state
    else
      task =
        Task.Supervisor.async_nolink(BacksBacksBacks.TabOrganizer.TaskSupervisor, fn ->
          TabOrganizer.organize_user(user, force: false, broadcast: true)
        end)

      %{
        state
        | running: MapSet.put(state.running, user.id),
          refs: Map.put(state.refs, task.ref, user.id)
      }
    end
  end

  defp pop_ref(state, ref) do
    {user_id, refs} = Map.pop(state.refs, ref)

    {user_id,
     %{
       state
       | refs: refs,
         running: if(user_id, do: MapSet.delete(state.running, user_id), else: state.running)
     }}
  end

  defp online?(user) do
    Presence.list("tabs:user:#{user.public_id}")
    |> map_size()
    |> Kernel.>(0)
  end

  defp schedule_tick(delay_ms) do
    Process.send_after(self(), :tick, delay_ms)
  end

  defp interval_ms do
    Application.get_env(:backs_backs_backs, TabOrganizer, [])
    |> Keyword.get(:scheduler_interval_ms, 300_000)
  end
end
