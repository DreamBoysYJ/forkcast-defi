package io.forkcast.backend.job.domain;


import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name="job_run")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class JobRun {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "job_name", nullable = false, length = 100)
  private String jobName;

  @Column(name="started_at")
  private Instant startedAt;

  @Column(name="finished_at")
  private Instant finishedAt;

  @Enumerated(EnumType.STRING)
  @Column(name="status", nullable = false, length=30)
  private JobRunStatus status;

  @Column(name ="error_message")
  private String errorMessage;

  @Column(name="range_start_block")
  private Long rangeStartBlock;

  @Column(name="range_end_block")
  private Long rangeEndBlock;

  public JobRun(String jobName, Long rangeStartBlock, Long rangeEndBlock) {
    this.jobName = jobName;
    this.rangeStartBlock = rangeStartBlock;
    this.rangeEndBlock = rangeEndBlock;
    this.status = JobRunStatus.STARTED;
    this.startedAt = Instant.now();
  }

  public static JobRun start(String jobName, Long rangeStartBlock, Long rangeEndBlock) {
    return new JobRun(jobName, rangeStartBlock, rangeEndBlock);
  }

  public void markSuccess() {
    this.status = JobRunStatus.SUCCESS;
    this.finishedAt = Instant.now();
    this.errorMessage = null;
  }

  public void markFailed(String errorMessage) {
    this.status = JobRunStatus.FAILED;
    this.finishedAt = Instant.now();
    this.errorMessage = errorMessage;
  }

  public void markSkipped() {
    this.status = JobRunStatus.SKIPPED;
    this.finishedAt = Instant.now();
    this.errorMessage = null;
  }
}
