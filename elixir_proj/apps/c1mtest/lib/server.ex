require Lager
defmodule Server do
  def start do
    start_log
    {:ok, info_pid} = Info.start_link
    accept(listen_tcp(10000), info_pid)
  end

  defp listen_tcp(port) do
    IO.puts "listening on #{port}"
    {:ok, listen_socket} = :gen_tcp.listen(port, [
      {:packet, :line},
      {:active, false},
      {:reuseaddr, true},
      {:nodelay, true}])
    listen_socket
  end

  defp accept(listen_socket, info_proc) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        {:ok, pid} = Receiver.start_link(info_proc)
        :ok = :gen_tcp.controlling_process(socket, pid)
        Receiver.process_conn(pid, socket)
      {:error, reason} ->
        Lager.error("Failed TCP accept: ~w", [reason])
    end
    accept(listen_socket, info_proc)
  end

  defp start_log do
    {:ok, _} = Application.ensure_all_started(:exlager)
    Lager.set_loglevel(:lager_console_backend, :debug)
  end

end

defmodule Info do
  use GenServer

  defmodule State do
    defstruct total_clients: 0,
      active_clients: 0
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [], [])
  end

  def add_client(pid) do
    GenServer.call(pid, :add)
  end

  def del_client(pid) do
    GenServer.cast(pid, :del)
  end

  def init([]) do
    {:ok, %State{}}
  end

  def handle_call(:add, _from, state) do
    total_clients = state.total_clients + 1
    active_clients = state.active_clients + 1
    {:reply, {total_clients, active_clients}, %State{state | 
        total_clients: total_clients, active_clients: active_clients}}
  end

  def handle_cast(:del, state) do
    active_clients = state.active_clients - 1
    {:noreply, %State{state | active_clients: active_clients}}
  end
end

defmodule Receiver do
  use GenServer

  defmodule State do
    defstruct info_pid: nil
  end

  def start_link(info_proc) do
    GenServer.start_link(__MODULE__, [info_proc], [])
  end

  def init([info_proc]) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, %State{info_pid: info_proc}}
  end

  def process_conn(pid, socket) do
    GenServer.cast(pid, {:handle_socket, socket})
  end

  def handle_cast({:handle_socket, socket}, state) do
    :inet.setopts(socket, active: :once)
    {total_clients, active_clients} = Info.add_client(state.info_pid)
    msg = "Hello, client #{total_clients}:#{active_clients}"
    Lager.info "new clients: #{msg}"
    :ok = :gen_tcp.send(socket, msg <> "\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, state) do 
    :inet.setopts(socket, [{:active, :once}])
    :gen_tcp.send(socket, data)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _tcp_socket}, state) do
    Info.del_client(state.info_pid)
    {:stop, :normal, state}
  end
end
