package io.forkcast.backend.sync.service;


import io.forkcast.backend.chain.client.EventLogDecoder;
import io.forkcast.backend.chain.service.RawChainEventService;
import io.forkcast.backend.chain.support.EventTopics;
import io.forkcast.backend.job.domain.JobRun;
import io.forkcast.backend.job.service.JobLockService;
import io.forkcast.backend.job.service.JobRunService;
import io.forkcast.backend.pool.service.PoolPriceEventService;
import io.forkcast.backend.position.service.PositionTimelineService;
import io.forkcast.backend.position.service.StrategyPositionService;
import io.forkcast.backend.sync.client.Web3jChainClient;
import io.forkcast.backend.sync.config.SyncProperties;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.web3j.protocol.core.methods.response.Log;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import static io.forkcast.backend.chain.support.EventTopics.*;

@Service
@Transactional
public class EventSyncService {

  private static final String JOB_NAME = "event-sync";
  private static final String CURSOR_NAME = "event-sync-finalized";
  private static final String LOCKED_BY = "local-instance";
  private static final long SAFE_HEAD_OFFSET = 5L;

  private final JobLockService jobLockService;
  private final JobRunService jobRunService;
  private final SyncCursorService syncCursorService;
  private final SyncProperties syncProperties;
  private final EventLogDecoder eventLogDecoder;
  private final RawChainEventService rawChainEventService;
  private final Web3jChainClient web3jChainClient;
  private final PoolPriceEventService poolPriceEventService;
  private final StrategyPositionService strategyPositionService;
  private final PositionTimelineService positionTimelineService;


  public EventSyncService(
    JobLockService jobLockService,
    JobRunService jobRunService,
    SyncCursorService syncCursorService,
    SyncProperties syncProperties,
    EventLogDecoder eventLogDecoder,
    RawChainEventService rawChainEventService,
    Web3jChainClient web3jChainClient, PoolPriceEventService poolPriceEventService, StrategyPositionService strategyPositionService, PositionTimelineService positionTimelineService
  ) {
    this.jobLockService = jobLockService;
    this.jobRunService = jobRunService;
    this.syncCursorService = syncCursorService;
    this.syncProperties = syncProperties;
    this.eventLogDecoder = eventLogDecoder;
    this.rawChainEventService = rawChainEventService;
    this.web3jChainClient = web3jChainClient;
    this.poolPriceEventService = poolPriceEventService;
    this.strategyPositionService = strategyPositionService;
    this.positionTimelineService = positionTimelineService;
  }

  public EventSyncResult run() {
    Instant startedAt = Instant.now();
    String lockOwner = UUID.randomUUID().toString();

    boolean acquired = jobLockService.tryAcquire(
      JOB_NAME,
      lockOwner,
      Duration.ofMinutes(2)
    );

    if (!acquired) {
      Instant finishedAt = Instant.now();
      return EventSyncResult.skipped(
        JOB_NAME,
        "already running",
        startedAt,
        finishedAt
      );
    }

    JobRun jobRun = null;

    try {
      long latestBlock = web3jChainClient.getLatestBlockNumber();
      long safeHead = Math.max(0L, latestBlock - SAFE_HEAD_OFFSET);
      long initialCursor = Math.max(
        0L,
        safeHead - syncProperties.getBootstrapWindowBlocks()
      );
      long currentLastSyncedBlock = syncCursorService
        .getOrCreate(CURSOR_NAME, initialCursor)
        .getLastSyncedBlock();
      long rangeStartBlock = currentLastSyncedBlock + 1;
      long rangeEndBlock = safeHead;


      if (rangeEndBlock < rangeStartBlock) {
        Instant finishedAt = Instant.now();
        return EventSyncResult.skipped(
          JOB_NAME,
          "no finalized block range",
          startedAt,
          finishedAt
        );
      }



      jobRun = jobRunService.start(JOB_NAME, rangeStartBlock, rangeEndBlock);
      String strategyRouterAddress = syncProperties.getContracts().getStrategyRouterAddress();
      String hookAddress = syncProperties.getContracts().getHookAddress();

      List<Log> routerLogs =
        web3jChainClient.getLogs(
          strategyRouterAddress,
          List.of(
            POSITION_OPENED,
            POSITION_CLOSED,
            FEES_COLLECTED
          ),
          rangeStartBlock,
          rangeEndBlock
        );

      List<Log> hookLogs =
        web3jChainClient.getLogs(
          hookAddress,
          List.of(EventTopics.SWAP_PRICE_LOGGED),
          rangeStartBlock,
          rangeEndBlock
        );

      List<Log> logs = new ArrayList<>(routerLogs.size() + hookLogs.size());
      logs.addAll(routerLogs);
      logs.addAll(hookLogs);
      logs.sort(
        Comparator
          .comparing((Log log) -> log.getBlockNumber().longValue())
          .thenComparing(log -> log.getLogIndex().intValue())
      );

      int processedEvents = 0;
      for (Log log : logs) {
        EventLogDecoder.DecodedEvent decodedEvent = eventLogDecoder.decode(log);
        boolean inserted = rawChainEventService.saveIfAbsent(decodedEvent, log);

        if (!inserted) {
          continue;
        }


        if ("SwapPriceLogged".equals(decodedEvent.eventName())) {
          poolPriceEventService.saveIfAbsent(decodedEvent, log);
        }

        if ("PositionOpened".equals(decodedEvent.eventName())) {
          strategyPositionService.applyOpened(decodedEvent);
          positionTimelineService.appendOpened(decodedEvent);
        }

        if ("FeesCollected".equals(decodedEvent.eventName())) {
          positionTimelineService.appendFeesCollected(decodedEvent);
        }

        if ("PositionClosed".equals(decodedEvent.eventName())) {
          strategyPositionService.applyClosed(decodedEvent);
          positionTimelineService.appendClosed(decodedEvent);
        }

        processedEvents++;
      }


      Long updatedCursor = rangeEndBlock;

      syncCursorService.advance(CURSOR_NAME, rangeEndBlock);
      jobRunService.markSuccess(jobRun.getId());
      Instant finishedAt = Instant.now();
      return EventSyncResult.success(
        JOB_NAME,
        rangeStartBlock,
        rangeEndBlock,
        processedEvents,
        updatedCursor,
        startedAt,
        finishedAt
      );


    } catch (Exception e) {
      if (jobRun != null){
        jobRunService.markFailed(jobRun.getId() , e.getMessage());

      }
      throw e;
    } finally {
      jobLockService.release(JOB_NAME, lockOwner);
    }

  }


  public record EventSyncResult(
    String jobName,
    String status,
    String reason,
    Long rangeStartBlock,
    Long rangeEndBlock,
    int processedEvents,
    Long updatedCursor,
    Instant startedAt,
    Instant finishedAt
  ) {
    public static EventSyncResult success(
      String jobName,
      Long rangeStartBlock,
      Long rangeEndBlock,
      int processedEvents,
      Long updatedCursor,
      Instant startedAt,
      Instant finishedAt
    ) {
      return new EventSyncResult(
        jobName,
        "SUCCESS",
        null,
        rangeStartBlock,
        rangeEndBlock,
        processedEvents,
        updatedCursor,
        startedAt,
        finishedAt
      );
    }

    public static EventSyncResult skipped(
      String jobName,
      String reason,
      Instant startedAt,
      Instant finishedAt
    ) {
      return new EventSyncResult(
        jobName,
        "SKIPPED",
        reason,
        null,
        null,
        0,
        null,
        startedAt,
        finishedAt
      );
    }
  }
}
