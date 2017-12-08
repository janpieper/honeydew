defmodule Honeydew.FailureMode.MoveTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  setup do
    queue = :erlang.unique_integer
    failure_queue = "#{queue}_failed"

    {:ok, _} = Helper.start_queue_link(queue, failure_mode: {Honeydew.FailureMode.Move, queue: failure_queue})
    {:ok, _} = Helper.start_queue_link(failure_queue)
    {:ok, _} = Helper.start_worker_link(queue, Stateless)

    [queue: queue, failure_queue: failure_queue]
  end

  test "validate_args!/1" do
    import Honeydew.FailureMode.Move, only: [validate_args!: 1]

    assert :ok = validate_args!(queue: :abc)
    assert :ok = validate_args!(queue: {:global, :abc})

    assert_raise ArgumentError, fn ->
      validate_args!(:abc)
    end
  end

  test "should move the job on the new queue", %{queue: queue, failure_queue: failure_queue} do
    {:crash, [self()]} |> Honeydew.async(queue)
    assert_receive :job_ran

    Process.sleep(500) # let the failure mode do its thing

    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 0
    refute_receive :job_ran

    assert Honeydew.status(failure_queue) |> get_in([:queue, :count]) == 1
  end

  test "should inform the awaiting process of the error", %{queue: queue, failure_queue: failure_queue} do
    job = {:crash, [self()]} |> Honeydew.async(queue, reply: true)

    assert {:moved, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)

    {:ok, _} = Helper.start_worker_link(failure_queue, Stateless)

    # job ran in the failure queue
    assert {:error, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
  end
end
