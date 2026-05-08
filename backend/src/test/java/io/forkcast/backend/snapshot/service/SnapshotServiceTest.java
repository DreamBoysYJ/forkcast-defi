package io.forkcast.backend.snapshot.service;

import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.domain.JobRunStatus;
import io.forkcast.backend.job.repository.JobLockRepository;
import io.forkcast.backend.job.repository.JobRunRepository;
import io.forkcast.backend.position.domain.StrategyPosition;
import io.forkcast.backend.position.repository.StrategyPositionRepository;
import io.forkcast.backend.snapshot.client.StrategyLensClient;
import io.forkcast.backend.snapshot.domain.PositionSnapshot;
import io.forkcast.backend.snapshot.repository.PositionSnapshotRepository;
import io.forkcast.backend.sync.client.Web3jChainClient;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
  "sync.rpc.url=http://localhost:8545",
  "sync.contracts.strategy-router-address=0x0000000000000000000000000000000000000000",
  "sync.contracts.hook-address=0x0000000000000000000000000000000000000000",
  "STRATEGY_LENS_ADDRESS=0x0000000000000000000000000000000000000000"
})
class SnapshotServiceTest {

  @Autowired
  private SnapshotService snapshotService;

  @Autowired
  private StrategyPositionRepository strategyPositionRepository;

  @Autowired
  private PositionSnapshotRepository positionSnapshotRepository;

  @Autowired
  private JobRunRepository jobRunRepository;

  @Autowired
  private JobLockRepository jobLockRepository;

  @MockitoBean
  private Web3jChainClient web3jChainClient;

  @MockitoBean
  private StrategyLensClient strategyLensClient;

  @BeforeEach
  void setUp() {
    positionSnapshotRepository.deleteAll();
    strategyPositionRepository.deleteAll();
    jobRunRepository.deleteAll();
    jobLockRepository.deleteAll();
  }

  @Test
  void runSavesSuccessfulSnapshotsAndSkipsFailedPositions() {
    StrategyPosition first = new StrategyPosition(
      1L,
      "0x0000000000000000000000000000000000000001",
      "0x0000000000000000000000000000000000000101",
      "0x0000000000000000000000000000000000000201",
      "0x0000000000000000000000000000000000000301",
      true,
      10L,
      null,
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      null
    );

    StrategyPosition second = new StrategyPosition(
      2L,
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000102",
      "0x0000000000000000000000000000000000000202",
      "0x0000000000000000000000000000000000000302",
      true,
      11L,
      null,
      "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      null
    );

    strategyPositionRepository.saveAll(List.of(first, second));

    when(web3jChainClient.getLatestBlockNumber()).thenReturn(12345L);
    when(strategyLensClient.getPositionState(
      eq(first.getOwnerAddress()),
      eq(first.getTokenId()),
      eq(12345L)
    )).thenReturn(successState());
    when(strategyLensClient.getPositionState(
      eq(second.getOwnerAddress()),
      eq(second.getTokenId()),
      eq(12345L)
    )).thenThrow(new IllegalStateException("rpc timeout"));

    SnapshotService.SnapshotResult result = snapshotService.run();

    assertThat(result.status()).isEqualTo("SUCCESS");
    assertThat(result.snapshottedPositions()).isEqualTo(1);
    assertThat(result.observedBlockNumber()).isEqualTo(12345L);

    List<PositionSnapshot> snapshots = positionSnapshotRepository.findAll();
    assertThat(snapshots).hasSize(1);
    assertThat(snapshots.get(0).getTokenId()).isEqualTo(1L);
    assertThat(snapshots.get(0).getObservedBlockNumber()).isEqualTo(12345L);

    List<JobRun> jobRuns = jobRunRepository.findAll();
    assertThat(jobRuns).singleElement().satisfies(jobRun -> {
      assertThat(jobRun.getJobName()).isEqualTo("snapshot");
      assertThat(jobRun.getStatus()).isEqualTo(JobRunStatus.SUCCESS);
      assertThat(jobRun.getStartedAt()).isNotNull();
      assertThat(jobRun.getFinishedAt()).isNotNull();
      assertThat(jobRun.getErrorMessage()).isNull();
    });
  }

  private StrategyLensClient.PositionState successState() {
    return new StrategyLensClient.PositionState(
      BigInteger.valueOf(1000L),
      BigInteger.valueOf(2000L),
      BigInteger.valueOf(3000L),
      181,
      BigInteger.valueOf(4000L),
      BigInteger.valueOf(5000L),
      BigInteger.valueOf(6000L),
      new BigDecimal("1.234567890123456789")
    );
  }
}
