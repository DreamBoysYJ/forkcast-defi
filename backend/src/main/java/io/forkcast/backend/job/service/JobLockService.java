package io.forkcast.backend.job.service;


import io.forkcast.backend.job.domain.JobLock;
import io.forkcast.backend.job.repository.JobLockRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;

@Service
public class JobLockService {

  private final JobLockRepository jobLockRepository;

  public JobLockService(JobLockRepository jobLockRepository) {
    this.jobLockRepository = jobLockRepository;
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public boolean tryAcquire(String jobName, String lockedBy, Duration leaseDuration) {
    Instant now = Instant.now();
    Instant lockedUntil = now.plus(leaseDuration);

    int updated = jobLockRepository.tryAcquire(jobName, lockedUntil, lockedBy, now);

    return updated == 1;


  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void release(String jobName, String lockedBy) {
    jobLockRepository.release(jobName, lockedBy, Instant.now());
  }
}
