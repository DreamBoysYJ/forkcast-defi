package io.forkcast.backend.job.service;


import io.forkcast.backend.job.domain.JobLock;
import io.forkcast.backend.job.repository.JobLockRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;

@Service
@Transactional
public class JobLockService {

  private final JobLockRepository jobLockRepository;

  public JobLockService(JobLockRepository jobLockRepository) {
    this.jobLockRepository = jobLockRepository;
  }

  public boolean tryAcquire(String jobName, String lockedBy, Duration leaseDuration) {
    Instant now = Instant.now();
    Instant lockedUntil = now.plus(leaseDuration);

    JobLock lock = jobLockRepository.findById(jobName).orElse(null);

    if (lock == null) {
      jobLockRepository.save(new JobLock(jobName, lockedUntil, lockedBy));
      return true;
    }

    if (lock.isExpiredAt(now)) {
      lock.acquireUntil(lockedUntil, lockedBy);
      return true;
    }

    return false;
  }

  public void release(String jobName) {
    JobLock lock = jobLockRepository.findById(jobName).orElse(null);
    if (lock == null) {
      return;
    }
    lock.releaseAt(Instant.now());
  }
}
