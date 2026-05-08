package io.forkcast.backend.job.service;

import io.forkcast.backend.job.repository.JobLockRepository;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(properties = {
  "sync.rpc.url=http://localhost:8545",
  "sync.contracts.strategy-router-address=0x0000000000000000000000000000000000000000",
  "sync.contracts.hook-address=0x0000000000000000000000000000000000000000",
  "STRATEGY_LENS_ADDRESS=0x0000000000000000000000000000000000000000"
})
class JobLockServiceTest {

  private static final Duration LEASE_DURATION = Duration.ofMinutes(2);

  @Autowired
  private JobLockService jobLockService;

  @Autowired
  private JobLockRepository jobLockRepository;

  @BeforeEach
  void setUp() {
    jobLockRepository.deleteAll();
  }

  @Test
  void tryAcquireFailsWhileLeaseIsStillActive() {
    boolean first = jobLockService.tryAcquire("event-sync", "owner-a", LEASE_DURATION);
    boolean second = jobLockService.tryAcquire("event-sync", "owner-b", LEASE_DURATION);

    assertThat(first).isTrue();
    assertThat(second).isFalse();
  }

  @Test
  void releaseOnlyReleasesOwnedLock() {
    boolean acquired = jobLockService.tryAcquire("event-sync", "owner-a", LEASE_DURATION);

    jobLockService.release("event-sync", "owner-b");
    boolean afterWrongRelease = jobLockService.tryAcquire("event-sync", "owner-c", LEASE_DURATION);

    jobLockService.release("event-sync", "owner-a");
    boolean afterRightRelease = jobLockService.tryAcquire("event-sync", "owner-c", LEASE_DURATION);

    assertThat(acquired).isTrue();
    assertThat(afterWrongRelease).isFalse();
    assertThat(afterRightRelease).isTrue();
  }
}
