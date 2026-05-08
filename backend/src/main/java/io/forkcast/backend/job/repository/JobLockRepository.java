package io.forkcast.backend.job.repository;

import io.forkcast.backend.job.domain.JobLock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;

public interface JobLockRepository extends JpaRepository<JobLock, String> {

  @Modifying
  @Query(value = """
    INSERT INTO job_lock (job_name, locked_until, locked_by, updated_at)
    VALUES (:jobName, :lockedUntil, :lockedBy, :now)
    ON CONFLICT (job_name) DO UPDATE
      SET locked_until = :lockedUntil,
          locked_by = :lockedBy,
          updated_at = :now
      WHERE job_lock.locked_until <= :now
""", nativeQuery = true)
  int tryAcquire(
    @Param("jobName") String jobName,
    @Param("lockedUntil") Instant lockedUntil,
    @Param("lockedBy") String lockedBy,
    @Param("now") Instant now
    );


  @Modifying
  @Query("""
    update JobLock j
       set j.lockedUntil = :now,
           j.updatedAt = :now
     where j.jobName = :jobName
       and j.lockedBy = :lockedBy
    """)
  int release(
    @Param("jobName") String jobName,
    @Param("lockedBy") String lockedBy,
    @Param("now") Instant now
  );
}
