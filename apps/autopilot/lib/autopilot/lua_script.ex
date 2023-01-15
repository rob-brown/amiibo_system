defmodule Autopilot.LuaScript do
  def run_file(path) do
    path
    |> Path.expand()
    |> File.read!()
    |> run_string()
  end

  def run_string(code) do
    :luerl_sandbox.init()
    |> add_function("sleep", &sleep/2)
    |> add_function("wait_until_found", &wait_until_found/2)
    |> add_function("wait_until_gone", &wait_until_gone/2)
    |> add_function("capture", &capture/2)
    |> add_function("capture_crop", &capture_crop/2)
    |> add_function("press", &press/2)
    |> add_function("visible", &visible/2)
    |> add_function("count", &count/2)
    |> add_function("count_crop", &count_crop/2)
    |> run(code)
    |> case do
      {:error, reason} ->
        {:error, reason}

      {:ok, _lua_state} ->
        :ok
    end
  end

  ## Helpers

  defp add_function(state, path, function) when is_binary(path) and is_function(function, 2) do
    :luerl.set_table([path], function, state)
  end

  defp run(state, code) do
    case :luerl_sandbox.run(code, state, 0, [], :infinity) do
      {:error, e} -> {:error, e}
      {_result, new_state} -> {:ok, new_state}
    end
  end

  defp sleep([duration | _], lua_state) do
    duration = parse_duration(duration)
    Process.sleep(duration)
    {[], lua_state}
  end

  defp wait_until_found(lua_state, [target, timeout | _])
       when is_binary(target) and is_number(timeout) do
    Vision.wait_until_found(target, timeout)
    {[], lua_state}
  end

  defp wait_until_gone(lua_state, [target, timeout | _])
       when is_binary(target) and is_number(timeout) do
    Vision.wait_until_gone(target, timeout)
    {[], lua_state}
  end

  defp capture(lua_state, [save_path | _]) when is_binary(save_path) do
    Vision.capture(save_path)
    {[], lua_state}
  end

  defp capture_crop(lua_state, [save_path, top, left, bottom, right | _])
       when is_binary(save_path) and is_number(top) and is_number(left) and is_number(bottom) and
              is_number(right) do
    Vision.capture_crop(save_path, {top, left}, {bottom, right})
    {[], lua_state}
  end

  defp press(lua_state, [button, duration | _]) when is_binary(button) do
    duration = parse_duration(duration)
    Joycontrol.command("press #{button} #{duration}")
    {[], lua_state}
  end

  defp visible(lua_state, [target | _]) when is_binary(target) do
    result = Vision.visible(target)
    {[result], lua_state}
  end

  defp count(lua_state, [target | _]) when is_binary(target) do
    result = Vision.count(target)
    {[result], lua_state}
  end

  defp count_crop(lua_state, [target, top, left, bottom, right | _])
       when is_binary(target) and is_number(top) and is_number(left) and is_number(bottom) and
              is_number(right) do
    result = Vision.count_crop(target, %{top: top, left: left, bottom: bottom, right: right})
    {[result], lua_state}
  end

  @doc """
  Parses the duration into milliseconds. Assumes milliseconds
  when no unit present. Decimal points are not allowed.

  Examples:

      iex> Autopilot.LuaScript.parse_duration("1000ms")
      1000

      iex> Autopilot.LuaScript.parse_duration("10s")
      10000

      iex> Autopilot.LuaScript.parse_duration("500")
      500

      iex> Autopilot.LuaScript.parse_duration(1500)
      1500
  """
  def parse_duration(duration) when is_binary(duration) do
    cond do
      String.ends_with?(duration, "ms") ->
        duration
        |> String.trim_trailing("ms")
        |> String.to_integer()

      String.ends_with?(duration, "s") ->
        duration
        |> String.trim_trailing("s")
        |> String.to_integer()
        |> Kernel.*(1000)

      true ->
        String.to_integer(duration)
    end
  end

  def parse_duration(duration) when is_integer(duration) do
    duration
  end
end
