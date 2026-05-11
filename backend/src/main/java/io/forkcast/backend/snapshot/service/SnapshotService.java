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
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
@Slf4j
public class SnapshotService {
  private static final String JOB_NAME = "snapshot";
  private static final String LOCKED_BY = "local-instance";

  private final JobLockService jobLockService;
  private final JobRunService jobRunService;
  private final PositionSnapshotRepository positionSnapshotRepository;
  private final Web3jChainClient web3jChainClient;
  private final StrategyPositionRepository strategyPositionRepository;
  private final StrategyLensClient strategyLensClient;
  private final SnapshotWriteService snapshotWriteService;

  public SnapshotService(JobLockService jobLockService, JobRunService jobRunService, PositionSnapshotRepository positionSnapshotRepository, Web3jChainClient web3jChainClient, StrategyPositionRepository strategyPositionRepository, StrategyLensClient strategyLensClient, SnapshotWriteService snapshotWriteService) {
    this.jobLockService = jobLockService;
    this.jobRunService = jobRunService;
    this.positionSnapshotRepository = positionSnapshotRepository;
    this.web3jChainClient = web3jChainClient;
    this.strategyPositionRepository = strategyPositionRepository;
    this.strategyLensClient = strategyLensClient;
    this.snapshotWriteService = snapshotWriteService;
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
      List<PositionSnapshot> snapshots = new ArrayList<>();
      int failedPositions = 0;

//      int snapshottedPositions = 0;

      for (StrategyPosition position : openPositions) {
        try {
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

          snapshots.add(snapshot);
        } catch (Exception e) {
          failedPositions++;
          log.warn(
            "failed to collect snapshot. tokenId={}, ownerAddress={}",
            position.getTokenId(),
            position.getOwnerAddress(),
            e
          );
        }
      }

      snapshotWriteService.saveAll(snapshots);
      jobRunService.markSuccess(jobRun.getId());

      if (failedPositions > 0) {
        log.warn(
          "snapshot completed with partial failures. successCount={}, failedCount={}",
          snapshots.size(),
          failedPositions
        );
      }

      return SnapshotResult.success(
        JOB_NAME,
        snapshots.size(),
        observedBlockNumber,
        startedAt,
        Instant.now()
      );
    } catch (Exception e) {
      if (jobRun != null) {
        try {
          jobRunService.markFailed(jobRun.getId(), e.getMessage());

        } catch (Exception logFailure) {
          log.warn("failed to mark snapshot job_run as FAILED. jobRunId={}", jobRun.getId(), logFailure);

        }
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
