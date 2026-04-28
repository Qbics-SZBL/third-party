module dlf_qbics_mpi_bridge_state
  implicit none
  integer, save :: qbics_nprocs = 1
  integer, save :: qbics_iam = 0
  integer, save :: qbics_global_comm = 0
  integer, save :: qbics_ntasks = 1
  integer, save :: qbics_nprocs_per_task = 1
  integer, save :: qbics_iam_in_task = 0
  integer, save :: qbics_mytask = 0
  integer, save :: qbics_task_comm = 0
  integer, save :: qbics_ax_tasks_comm = 0
  logical, save :: has_procinfo = .false.
  logical, save :: has_taskfarm = .false.
end module dlf_qbics_mpi_bridge_state

subroutine dlf_put_procinfo(dlf_nprocs, dlf_iam, dlf_global_comm)
  use dlf_qbics_mpi_bridge_state
  implicit none
  integer, intent(in) :: dlf_nprocs, dlf_iam, dlf_global_comm

  qbics_nprocs = dlf_nprocs
  qbics_iam = dlf_iam
  qbics_global_comm = dlf_global_comm
  has_procinfo = .true.
end subroutine dlf_put_procinfo

subroutine dlf_get_procinfo(dlf_nprocs, dlf_iam, dlf_global_comm)
  use dlf_qbics_mpi_bridge_state
  implicit none
  include 'mpif.h'
  integer, intent(out) :: dlf_nprocs, dlf_iam, dlf_global_comm
  integer :: ierr
  logical :: tinitialized

  if (has_procinfo) then
    dlf_nprocs = qbics_nprocs
    dlf_iam = qbics_iam
    dlf_global_comm = qbics_global_comm
    return
  end if

  call mpi_initialized(tinitialized, ierr)
  if (ierr == 0 .and. tinitialized) then
    dlf_global_comm = mpi_comm_world
    call mpi_comm_rank(dlf_global_comm, dlf_iam, ierr)
    if (ierr /= 0) dlf_iam = 0
    call mpi_comm_size(dlf_global_comm, dlf_nprocs, ierr)
    if (ierr /= 0) dlf_nprocs = 1
  else
    dlf_nprocs = 1
    dlf_iam = 0
    dlf_global_comm = 0
  end if

  qbics_nprocs = dlf_nprocs
  qbics_iam = dlf_iam
  qbics_global_comm = dlf_global_comm
  has_procinfo = .true.
end subroutine dlf_get_procinfo

subroutine dlf_put_taskfarm(dlf_ntasks, dlf_nprocs_per_task, dlf_iam_in_task, &
    dlf_mytask, dlf_task_comm, dlf_ax_tasks_comm)
  use dlf_qbics_mpi_bridge_state
  implicit none
  integer, intent(in) :: dlf_ntasks, dlf_nprocs_per_task, dlf_iam_in_task
  integer, intent(in) :: dlf_mytask, dlf_task_comm, dlf_ax_tasks_comm

  qbics_ntasks = dlf_ntasks
  qbics_nprocs_per_task = dlf_nprocs_per_task
  qbics_iam_in_task = dlf_iam_in_task
  qbics_mytask = dlf_mytask
  qbics_task_comm = dlf_task_comm
  qbics_ax_tasks_comm = dlf_ax_tasks_comm
  has_taskfarm = .true.
end subroutine dlf_put_taskfarm

subroutine dlf_get_taskfarm(dlf_ntasks, dlf_nprocs_per_task, dlf_iam_in_task, &
    dlf_mytask, dlf_task_comm, dlf_ax_tasks_comm)
  use dlf_qbics_mpi_bridge_state
  implicit none
  integer, intent(out) :: dlf_ntasks, dlf_nprocs_per_task, dlf_iam_in_task
  integer, intent(out) :: dlf_mytask, dlf_task_comm, dlf_ax_tasks_comm

  if (has_taskfarm) then
    dlf_ntasks = qbics_ntasks
    dlf_nprocs_per_task = qbics_nprocs_per_task
    dlf_iam_in_task = qbics_iam_in_task
    dlf_mytask = qbics_mytask
    dlf_task_comm = qbics_task_comm
    dlf_ax_tasks_comm = qbics_ax_tasks_comm
    return
  end if

  if (.not. has_procinfo) then
    call dlf_get_procinfo(qbics_nprocs, qbics_iam, qbics_global_comm)
  end if

  dlf_ntasks = 1
  dlf_nprocs_per_task = qbics_nprocs
  dlf_iam_in_task = qbics_iam
  dlf_mytask = 0
  dlf_task_comm = qbics_global_comm
  dlf_ax_tasks_comm = qbics_global_comm

  qbics_ntasks = dlf_ntasks
  qbics_nprocs_per_task = dlf_nprocs_per_task
  qbics_iam_in_task = dlf_iam_in_task
  qbics_mytask = dlf_mytask
  qbics_task_comm = dlf_task_comm
  qbics_ax_tasks_comm = dlf_ax_tasks_comm
  has_taskfarm = .true.
end subroutine dlf_get_taskfarm
