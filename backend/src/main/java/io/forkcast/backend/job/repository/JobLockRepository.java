package io.forkcast.backend.job.repository;

import io.forkcast.backend.job.domain.JobLock;
import org.springframework.data.jpa.repository.JpaRepository;

public interface JobLockRepository extends JpaRepository<JobLock, String> {
}
