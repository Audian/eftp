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

defmodule Eftp.Client do
  @moduledoc """
  FTP Client functions
  """

  @doc """
  Connect to an ftp server. If successful, returns a PID. This pid must be 
  passed to the authenticate function.

  ## Examples
  ```elixir
  iex> Eftp.Client.connect("ftp.example.net", 21)
  #PID<0.158.0>
  ```
  """
  @spec connect(host :: String.t(), port :: Integer.t()) :: {:ok, Pid.t()} | {:error, term()}
  def connect(host, port \\ 21) do
    case :inets.start(:ftpc, host: '#{host}', port: '#{port}', progress: true) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Authenticate against an existing ftp server connection. If successful, returns a tuple with a pid. 
  This pid must be used for fetch/put commands.

  ## Examples
  ```elixir
  iex> Eftp.Client.authenticate(pid, "username", "password")
  #PID<0.158.0>
  ```
  """
  @spec authenticate({:ok, pid :: Pid.t()}, username :: String.t(), password :: String.t()) ::
          {:ok, Pid.t()} | {:error, term()}
  def authenticate({:ok, pid}, username, password) do
    case :ftp.user(pid, '#{username}', '#{password}') do
      :ok -> {:ok, pid}
      {:error, :euser} -> {:error, :invalid_auth}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec authenticate({:error, term()}, _username :: String.t(), _password :: String.t()) ::
          {:error, term()}
  def authenticate({:error, reason}, _username, _password), do: {:error, reason}

  @doc """
  Fetch a specific file from the server and save it to the supplied local path. A list of file 
  names can be passed and each file will be downloaded to the supplied local path
  """
  @spec fetch(
          {:ok, pid :: Pid.t()},
          remote_filename :: String.t(),
          local_save_path :: String.t()
        ) :: {:ok, String.t()} | {:error, term()}
  def fetch({:ok, pid}, remote_filename, local_save_path)
      when is_binary(remote_filename) do
    dir = Path.dirname(remote_filename)
    filename = Path.basename(remote_filename)
    save_filename = "#{local_save_path}/#{filename}"

    case File.exists?(save_filename) do
      true ->
        # backup the old name
        File.rename(save_filename, "#{save_filename}-#{unixtime()}.backup")
        fetch({:ok, pid}, remote_filename, local_save_path)

      false ->
        :ftp.cd(pid, '#{dir}')
        :ftp.type(pid, :binary)

        case :ftp.recv(pid, '#{filename}', '#{save_filename}') do
          :ok ->
            {:ok, save_filename}

          {:error, reason} ->
            File.rm(save_filename)
            {:error, reason}
        end
    end
  end

  @spec fetch({:ok, pid :: Pid.t()}, remote_files :: list(), local_save_path :: String.t()) ::
          {:ok, list()} | {:error, term()}
  def fetch({:ok, pid}, remote_files, local_save_path) when is_list(remote_files) do
    fetched_files =
      remote_files
      |> Enum.map(fn file -> fetch({:ok, pid}, file, local_save_path) end)
      |> Enum.map(fn {:ok, filename} -> filename end)

    {:ok, fetched_files}
  end

  @spec fetch({:error, reason :: term()}, _remote_files :: list(), _local_save_path :: String.t()) ::
          {:error, term()}
  def fetch({:error, reason}, _remote_files, _local_save_path), do: {:error, reason}

  @doc "Retrieves list of files from the current directory"
  @spec list({:ok, pid :: Pid.t()}) :: {:ok}
  def list({:ok, pid}) do
    case :ftp.nlist(pid) do
      {:ok, remote_files} ->
        files =
          remote_files
          |> List.to_string()
          |> String.split("\r\n")
          |> Enum.reject(fn file -> file == "" end)

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list({:error, reason :: term()}) :: {:error, term()}
  def list({:error, reason}), do: {:error, reason}

  @doc "Retrieve a list of files from the remote directory"
  @spec list({:ok, pid :: Pid.t()}, path :: String.t()) :: {:ok, list()} | {:error, term()}
  def list({:ok, pid}, path) do
    case :ftp.nlist(pid, '#{path}') do
      {:ok, remote_files} ->
        files =
          remote_files
          |> List.to_string()
          |> String.split("\r\n")
          |> Enum.reject(fn file -> file == "" end)

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list({:error, reason :: term()}, _path :: String.t()) :: {:error, term()}
  def list({:error, reason}, _path), do: {:error, reason}

  # -- private -- #

  # return unix time in seconds
  @spec unixtime() :: String.t()
  defp unixtime do
    unixtime = :os.system_time(:seconds)
    "#{unixtime}"
  end
end
