#
# Copyright 2023, Audian, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

defmodule Eftp do
  @moduledoc """
  Eftp is a simple wrapper for erlang's ftp client.
  """

  @app  Eftp.MixProject.project()[:app]
  @ver  Eftp.MixProject.project()[:version]
  @port 21

  @doc """
  Return the application version
  """
  @spec version() :: bitstring()
  def version(), do: "#{@app}-#{@ver}"

  @doc """
  Connect to an ftp server, and returns a pid. This pid must be passed to
  other functions.

  ## Examples
  ```elixir
  iex> Eftp.connect("ftp.example.net", 21)
  {:ok, #PID<0.158.0>}

  iex> Eftp.connect("ftp.example.net")
  {:ok, #PID<0.158.0>}

  iex> Eftp.connect("ftp.brokenexample.net", 21)
  {:error, :connection_failure}

  iex> Eftp.connect("ftp.example.net", "alpha")
  {:error, :invalid_props}
  ```
  """
  @spec connect(
    host  :: bitstring(),
    port  :: integer() | bitstring() | nil
  ) :: {:ok, pid()} | {:error, term()}
  def connect(host, port) when is_bitstring(host) and is_integer(port) do
    host = '#{host}'
    opts = [{'port', '#{port}'}]

    case :ftp.open(host, opts) do
      {:ok, pid}  -> {:ok, pid}
      {:error, _} -> {:error, :connection_failure}
    end
  end
  def connect(host, port) when is_bitstring(host) and is_bitstring(port) do
    case Integer.parse(port) do
      :error  -> {:error, :invalid_port}
      {p, _}  -> connect(host, p)
    end
  end
  def connect(_, _), do: {:error, :invalid_props}
  def connect(host) when is_bitstring(host) do
    connect(host, @port)
  end

  @doc """
  Authenticate against the ftp server. If successful returns the pid.

  ## Examples
  ```elixir
  iex> Eftp.authenticate({:ok, #PID<0.158.0>}, "user", "pass")
  {:ok, #PID<0.158.0>}

  iex> Eftp.authenticate({:ok, #PID<0.158.0>}, "nouser", "badpass")
  {:error, :authentication_failure}
  ```
  """
  @spec authenticate(
    {:ok, pid :: pid()} | {:error, term()},
    username  :: bitstring(),
    password  :: bitstring()
  ) :: {:ok, pid()} | {:error, term()}
  def authenticate({:ok, pid}, username, password) when is_bitstring(username) and
                                                        is_bitstring(password) do
    case :ftp.user(pid, '#{username}', '#{password}') do
      :ok -> {:ok, pid}
      {:error, :euser}  -> {:error, :authentication_failure}
      {:error, reason}  -> {:error, reason}
    end
  end
  def authenticate({:error, reason}, _, _), do: {:error, reason}

  @doc """
  Fetch a specific file from the server and save it to the local path. You can also
  pass a list of filenames (with the full remote path) and each file will be
  downloaded
  """
  @spec fetch(
    {:ok, pid   :: pid()} | {:error, term()},
    remote_file :: bitstring() | nonempty_list(),
    local_path  :: bitstring(),
    xfer_type   :: atom() | nil
  ) :: {:ok, bitstring()} | {:error, term()}
  def fetch({:ok, pid}, remote_file, local_path, xfer_type)
    when is_bitstring(remote_file) and is_bitstring(local_path) and is_atom(xfer_type)
  do
    # setup our paths and filenames
    dirname   = Path.dirname(remote_file)
    filename  = Path.basename(remote_file)

    # if a file with the same name exists, then rename our new file to have
    # a timestamp appended
    save_name =
      case File.exists?("#{local_path}/#{filename}") do
        false -> "#{local_path}/#{filename}"
        true  -> "#{local_path}/#{filename}-#{unixtime()}"
      end

    :ftp.cd(pid, '#{dirname}')
    :ftp.type(pid, xfer_type)

    case :ftp.recv(pid, '#{filename}', '#{save_name}') do
      :ok               -> {:ok, save_name}
      {:error, reason}  -> {:error, reason}
    end
  end

  def fetch({:ok, pid}, remote_files, local_path, xfer_type)
    when  is_list(remote_files) and is_bitstring(local_path) and is_atom(xfer_type)
  do
    fetched_files =
      remote_files
      |> Enum.map(fn file -> fetch({:ok, pid}, file, local_path) end)
      |> Enum.map(fn {:ok, filename} -> filename end)

    {:ok, fetched_files}
  end
  def fetch({:error, reason}, _, _, _), do: {:error, reason}

  def fetch({:ok, pid}, remote_file, local_path), do: fetch({:ok, pid}, remote_file, local_path, :binary)
  def fetch({:error, reason}, _, _),    do: {:error, reason}

  @doc """
  Retrieve a list of files from the remote server
  """
  @spec list(
    {:ok, pid   :: pid()} | {:error, term()},
    remote_path :: bitstring()
  ) :: {:ok, list()} | {:error, term()}
  def list({:ok, pid}, remote_path) when is_bitstring(remote_path) do
    case :ftp.nlist(pid, '#{remote_path}') do
      {:error, reason}  -> {:error, reason}
      {:ok, filenames}  ->
        files =
          filenames
          |> List.to_string()
          |> String.split("\r\n")
          |> Enum.reject(fn file -> is_nil(file) or file == "" end)

        {:ok, files}
    end
  end
  def list({:ok, _}, _), do: {:error, :invalid_pathname}
  def list({:error, reason}, _), do: {:error, reason}

  # -- private -- #

  # return a unix timestamp
  @spec unixtime() :: bitstring()
  defp unixtime(), do: "#{:os.system_time(:seconds)}"
end
