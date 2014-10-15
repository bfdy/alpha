require Lager
defmodule Client do
  @max_conns  25000 #It fails at >28000
  def start do
    start_log
    connect('10.236.124.138', 10000, @max_conns)
  end

  defp connect(address, port, counter) do
    {:ok, socket} = :gen_tcp.connect(address, port, [{:packet, :line}, 
      {:active, false}, {:buffer, 100}])
    {:ok, msg} = :gen_tcp.recv(socket, 0)
    Lager.info msg
    counter = counter - 1
    if counter > 0 do
      connect(address, port, counter)
    else
      IO.gets "Press enter to exit"
    end
  end

  defp start_log do
    {:ok, _} = Application.ensure_all_started(:exlager)
    Lager.set_loglevel(:lager_console_backend, :debug)
  end

end
