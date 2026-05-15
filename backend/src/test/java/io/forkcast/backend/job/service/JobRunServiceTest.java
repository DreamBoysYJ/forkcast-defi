package io.forkcast.backend.job.service;

import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.domain.JobRunStatus;
import io.forkcast.backend.job.repository.JobRunRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.transaction.annotation.Transactional;

import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(properties = {
  "sync.rpc.url=http://localhost:8545",
  "sync.contracts.strategy-router-address=0x0000000000000000000000000000000000000000",
  "sync.contracts.hook-address=0x0000000000000000000000000000000000000000",
  "STRATEGY_LENS_ADDRESS=0x0000000000000000000000000000000000000000"
})
class JobRunServiceTest {

  @Autowired
  private JobRunRepository jobRunRepository;

  @Autowired
  private JobRunService jobRunService;

  @Autowired
  private JobRunRollbackProbe jobRunRollbackProbe;

  @Autowired
  private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    jobRunRepository.deleteAll();
  }

  @Test
  void startSurvivesOuterRollback() {
    assertThatThrownBy(() -> jobRunRollbackProbe.startAndRollback())
      .isInstanceOf(IllegalStateException.class)
      .hasMessage("force rollback after start");

    assertThat(jobRunRepository.findAll())
      .singleElement()
      .satisfies(jobRun -> {
        assertThat(jobRun.getJobName()).isEqualTo("event-sync");
        assertThat(jobRun.getStatus()).isEqualTo(JobRunStatus.STARTED);
        assertThat(jobRun.getStartedAt()).isNotNull();
      });
  }

  @Test
  void markFailedSurvivesOuterRollback() {
    assertThatThrownBy(() -> jobRunRollbackProbe.startMarkFailedAndRollback())
      .isInstanceOf(IllegalStateException.class)
      .hasMessage("force rollback after markFailed");

    assertThat(jobRunRepository.findAll())
      .singleElement()
      .satisfies(jobRun -> {
        assertThat(jobRun.getJobName()).isEqualTo("event-sync");
        assertThat(jobRun.getStatus()).isEqualTo(JobRunStatus.FAILED);
        assertThat(jobRun.getStartedAt()).isNotNull();
        assertThat(jobRun.getFinishedAt()).isNotNull();
        assertThat(jobRun.getErrorMessage()).isEqualTo("forced failure");
        assertThat(jobRun.getRangeStartBlock()).isEqualTo(100L);
        assertThat(jobRun.getRangeEndBlock()).isEqualTo(120L);
      });
  }

  @Test
  void purgeOlderThan_deletesOldAndKeepsRecent() {
    JobRun old = jobRunService.start("event-sync", null, null);
    jdbcTemplate.update(
      "UPDATE job_run SET started_at = NOW() - INTERVAL '15 days' WHERE id = ?",
      old.getId()
    );
    jobRunService.start("event-sync", null, null);

    int deleted = jobRunService.purgeOlderThan(14);

    assertThat(deleted).isEqualTo(1);
    assertThat(jobRunRepository.count()).isEqualTo(1);
  }

  @Test
  void purgeOlderThan_doesNotDeleteWhenNothingIsOld() {
    jobRunService.start("event-sync", null, null);

    int deleted = jobRunService.purgeOlderThan(14);

    assertThat(deleted).isEqualTo(0);
    assertThat(jobRunRepository.count()).isEqualTo(1);
  }

  @TestConfiguration
  static class JobRunRollbackProbeConfig {

    @Bean
    JobRunRollbackProbe jobRunRollbackProbe(JobRunService jobRunService) {
      return new JobRunRollbackProbe(jobRunService);
    }
  }

  static class JobRunRollbackProbe {

    private final JobRunService jobRunService;

    JobRunRollbackProbe(JobRunService jobRunService) {
      this.jobRunService = jobRunService;
    }

    @Transactional
    void startAndRollback() {
      jobRunService.start("event-sync", 100L, 120L);
      throw new IllegalStateException("force rollback after start");
    }

    @Transactional
    void startMarkFailedAndRollback() {
      JobRun jobRun = jobRunService.start("event-sync", 100L, 120L);
      jobRunService.markFailed(jobRun.getId(), "forced failure");
      throw new IllegalStateException("force rollback after markFailed");
    }
  }
}
