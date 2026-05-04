package io.forkcast.backend.job.repository;

import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.domain.JobRunStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface JobRunRepository extends JpaRepository<JobRun, Long> {

  List<JobRun> findTop20ByJobNameOrderByStartedAtDesc(String jobName);
  List<JobRun> findTop20ByStatusOrderByStartedAtDesc(JobRunStatus status);

}
