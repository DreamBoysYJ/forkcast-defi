package io.forkcast.backend.snapshot.service;


import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.service.JobLockService;
import io.forkcast.backend.job.service.JobRunService;
import io.forkcast.backend.position.domain.StrategyPosition;
import io.forkcast.backend.position.repository.StrategyPositionRepository;
import io.forkcast.backend.position.service.StrategyPositionService;
import io.forkcast.backend.snapshot.client.StrategyLensClient;
import io.forkcast.backend.snapshot.domain.PositionSnapshot;
import io.forkcast.backend.snapshot.repository.PositionSnapshotRepository;
import io.forkcast.backend.sync.client.Web3jChainClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
@Transactional
public class SnapshotService {
  private static final String JOB_NAME = "snapshot";
  private static final String LOCKED_BY = "local-instance";

  private final JobLockService jobLockService;
  private final JobRunService jobRunService;
  private final PositionSnapshotRepository positionSnapshotRepository;
  private final Web3jChainClient web3jChainClient;
  private final StrategyPositionRepository strategyPositionRepository;
  private final StrategyLensClient strategyLensClient;

  public SnapshotService(JobLockService jobLockService, JobRunService jobRunService, PositionSnapshotRepository positionSnapshotRepository, Web3jChainClient web3jChainClient, StrategyPositionRepository strategyPositionRepository, StrategyLensClient strategyLensClient) {
    this.jobLockService = jobLockService;
    this.jobRunService = jobRunService;
    this.positionSnapshotRepository = positionSnapshotRepository;
    this.web3jChainClient = web3jChainClient;
    this.strategyPositionRepository = strategyPositionRepository;
    this.strategyLensClient = strategyLensClient;
  }

  public SnapshotResult run() {
    Instant startedAt = Instant.now();
    String lockOwner = UUID.randomUUID().toString();

    boolean acquired = jobLockService.tryAcquire(
      JOB_NAME,
      lockOwner,
      Duration.ofMinutes(2)
    );

    if (!acquired) {
      return SnapshotResult.skipped(
        JOB_NAME,
        "already running",
        startedAt,
        Instant.now()
      );
    }

    JobRun jobRun = null;

    try {
      long observedBlockNumber = web3jChainClient.getLatestBlockNumber();
      Instant snapshotAt = Instant.now();

      jobRun = jobRunService.start(JOB_NAME, null, null);

      List<StrategyPosition> openPositions = strategyPositionRepository.findByIsOpenTrue();

      int snapshottedPositions = 0;

      for (StrategyPosition position : openPositions) {
        if (positionSnapshotRepository.existsByTokenIdAndSnapshotAt(position.getTokenId(), snapshotAt)) {
          continue;
        }

        StrategyLensClient.PositionState state = strategyLensClient.getPositionState(
          position.getOwnerAddress(),
          position.getTokenId(),
          observedBlockNumber
        );

        PositionSnapshot snapshot = new PositionSnapshot(
          position.getTokenId(),
          position.getOwnerAddress(),
          position.getVaultAddress(),
          position.getSupplyAsset(),
          position.getBorrowAsset(),
          position.isOpen(),
          state.liquidity(),
          state.amount0Now(),
          state.amount1Now(),
          state.currentTick(),
          state.sqrtPriceX96(),
          state.totalCollateralBase(),
          state.totalDebtBase(),
          state.healthFactor(),
          snapshotAt,
          observedBlockNumber
        );

        positionSnapshotRepository.save(snapshot);
        snapshottedPositions++;
      }

      jobRunService.markSuccess(jobRun.getId());

      return SnapshotResult.success(
        JOB_NAME,
        snapshottedPositions,
        observedBlockNumber,
        startedAt,
        Instant.now()
      );
    } catch (Exception e) {
      if (jobRun != null) {
        jobRunService.markFailed(jobRun.getId(), e.getMessage());
      }
      throw e;
    } finally {
      jobLockService.release(JOB_NAME, lockOwner);
    }
  }






  public record SnapshotResult(
    String jobName,
    String status,
    String reason,
    int snapshottedPositions,
    Long observedBlockNumber,
    Instant startedAt,
    Instant finishedAt
  ) {
    public static SnapshotResult success(
      String jobName,
      int snapshottedPositions,
      Long observedBlockNumber,
      Instant startedAt,
      Instant finishedAt
    ) {
      return new SnapshotResult(
        jobName,
        "SUCCESS",
        null,
        snapshottedPositions,
        observedBlockNumber,
        startedAt,
        finishedAt
      );
    }

    public static SnapshotResult skipped(
      String jobName,
      String reason,
      Instant startedAt,
      Instant finishedAt
    ) {
      return new SnapshotResult(
        jobName,
        "SKIPPED",
        reason,
        0,
        null,
        startedAt,
        finishedAt
      );
    }
  }


}
