defmodule Jellyfish.ConfigReader do
  @moduledoc false

  require Logger

  def read_port_range(env) do
    if value = System.get_env(env) do
      with [str1, str2] <- String.split(value, "-"),
           from when from in 0..65_535 <- String.to_integer(str1),
           to when to in from..65_535 and from <= to <- String.to_integer(str2) do
        {from, to}
      else
        _else ->
          raise("""
          Bad #{env} environment variable value. Expected "from-to", where `from` and `to` \
          are numbers between 0 and 65535 and `from` is not bigger than `to`, got: \
          #{value}
          """)
      end
    end
  end

  def read_ip(env) do
    if value = System.get_env(env) do
      value = value |> to_charlist()

      case :inet.parse_address(value) do
        {:ok, parsed_ip} ->
          parsed_ip

        _error ->
          raise("""
          Bad #{env} environment variable value. Expected valid ip address, got: #{value}"
          """)
      end
    end
  end

  def read_port(env) do
    if value = System.get_env(env) do
      case Integer.parse(value) do
        {port, _sufix} when port in 1..65_535 ->
          port

        _other ->
          raise("""
          Bad #{env} environment variable value. Expected valid port number, got: #{value}
          """)
      end
    end
  end

  def read_boolean(env) do
    if value = System.get_env(env) do
      String.downcase(value) not in ["false", "f", "0"]
    end
  end

  def read_dist_config() do
    if read_boolean("JF_DIST_ENABLED") do
      node_name_value = System.get_env("JF_DIST_NODE_NAME")
      cookie_value = System.get_env("JF_DIST_COOKIE", "panuozzo-pollo-e-pancetta")
      nodes_value = System.get_env("JF_DIST_NODES", "")

      unless node_name_value do
        raise "JF_DIST_ENABLED has been set but JF_DIST_NODE_NAME remains unset."
      end

      node_name = parse_node_name(node_name_value)
      cookie = parse_cookie(cookie_value)
      nodes = parse_nodes(nodes_value)

      if nodes == [] do
        Logger.warning("""
        JF_DIST_ENABLED has been set but JF_DIST_NODES remains unset.
        Make sure that at least one of your Jellyfish instances
        has JF_DIST_NODES set.
        """)
      end

      [enabled: true, node_name: node_name, cookie: cookie, nodes: nodes]
    else
      [enabled: false, node_name: nil, cookie: nil, nodes: []]
    end
  end

  defp parse_node_name(node_name), do: String.to_atom(node_name)
  defp parse_cookie(cookie_value), do: String.to_atom(cookie_value)

  defp parse_nodes(nodes_value) do
    nodes_value
    |> String.split(" ", trim: true)
    |> Enum.map(&String.to_atom(&1))
  end
end
