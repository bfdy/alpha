defmodule Gateway do
  @smtp_port 8025
  @http_proxy_port 8080

  def start(smtp_server, proxy_server) do
    for {port, remote_addr, remote_port} <- [
      {@smtp_port, smtp_server, 25},
      {@http_proxy_port, proxy_server, 80}] do
      {:ok, listen_socket} = :gen_tcp.listen(port, active: false, 
        reuseaddr: true, nodelay: true)

      spawn_link(fn -> make_tunnel(listen_socket, remote_addr, remote_port) end)
    end

    IO.gets "press ENTER to exit"
  end

  defp make_tunnel(l_socket, remote_addr, remote_port) do
    {:ok, client} = :gen_tcp.accept(l_socket)
    {:ok, pid} = Tunnel.start_link(remote_addr, remote_port)
    :ok = :gen_tcp.controlling_process(client, pid)
    Tunnel.process_conn(pid, client)
    make_tunnel(l_socket, remote_addr, remote_port)
  end
end

defmodule Tunnel do
  use GenServer

  defmodule State do
    defstruct remote_addr: "", remote_port: 0, out_conn: nil, in_conn: nil, 
      conns: 0
  end

  def start_link(remote_addr, remote_port) do
    GenServer.start_link(__MODULE__, [remote_addr, remote_port], [])
  end

  def init([remote_addr, remote_port]) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, %State{remote_addr: remote_addr, remote_port: remote_port}}
  end

  def process_conn(pid, socket) do
    GenServer.cast(pid, {:activate_socket, socket})
  end

  def handle_cast({:activate_socket, in_conn}, state) do
    IO.puts "\nconnect to #{state.remote_addr}, #{state.remote_port}"
    {:ok, out_conn} = state.remote_addr |> String.to_char_list 
      |> :gen_tcp.connect(state.remote_port, active: :once)

    :inet.setopts(in_conn, active: :once)

    {:noreply, %State{state|out_conn: out_conn, in_conn: in_conn, conns: 2}}
  end

  def handle_info({:tcp, socket, data}, %State{out_conn: socket}=state) do 
    :inet.setopts(socket, [{:active, :once}])
    :ok = :gen_tcp.send(state.in_conn, data)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, %State{in_conn: socket}=state) do 
    :inet.setopts(socket, [{:active, :once}])
    :ok = :gen_tcp.send(state.out_conn, data)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, %State{out_conn: out_conn, 
    in_conn: in_conn} = state) do
    case socket do
      ^out_conn ->
        :gen_tcp.shutdown(in_conn, :read)
      ^in_conn ->
        :gen_tcp.shutdown(out_conn, :read)
    end
    state = %State{state| conns: state.conns - 1}
    if state.conns > 0 do
      {:noreply, state}
    else
      IO.puts "\nclose connection to #{state.remote_addr}"
      {:stop, :normal, state}
    end
  end
end

