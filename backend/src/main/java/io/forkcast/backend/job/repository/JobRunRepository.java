package io.forkcast.backend.job.repository;

import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.domain.JobRunStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface JobRunRepository extends JpaRepository<JobRun, Long> {

  List<JobRun> findTop20ByJobNameOrderByStartedAtDesc(String jobName);
  List<JobRun> findTop20ByStatusOrderByStartedAtDesc(JobRunStatus status);

  @Modifying(clearAutomatically = true)
  @Query("DELETE FROM JobRun j WHERE j.startedAt < :cutoff")
  int deleteByStartedAtBefore(@Param("cutoff") Instant cutoff);

}
