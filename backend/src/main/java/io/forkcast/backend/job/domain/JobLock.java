package io.forkcast.backend.job.domain;


import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "job_lock")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class JobLock {

  @Id
  @Column(name = "job_name", nullable = false, length = 100)
  private String jobName;

  @Column(name = "locked_until", nullable = false)
  private Instant lockedUntil;

  @Column(name="locked_by", nullable = false, length = 255)
  private String lockedBy;

  @Column(name="updated_at", nullable = false)
  private Instant updatedAt;

  public JobLock(String jobName, Instant lockedUntil, String lockedBy) {
    this.jobName = jobName;
    this.lockedUntil = lockedUntil;
    this.lockedBy = lockedBy;
    this.updatedAt = Instant.now();
  }

  public boolean isExpiredAt(Instant now) {
    return !lockedUntil.isAfter(now);
  }

  public void acquireUntil(Instant lockedUntil, String lockedBy) {
    this.lockedUntil = lockedUntil;
    this.lockedBy = lockedBy;
    this.updatedAt = Instant.now();
  }

  public void releaseAt(Instant now) {
    this.lockedUntil = now;
    this.updatedAt = now;
  }
}
