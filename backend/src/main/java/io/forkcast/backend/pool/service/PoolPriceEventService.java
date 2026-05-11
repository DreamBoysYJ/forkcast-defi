package io.forkcast.backend.pool.service;


import io.forkcast.backend.chain.client.EventLogDecoder;
import io.forkcast.backend.pool.domain.PoolPriceEvent;
import io.forkcast.backend.pool.repository.PoolPriceEventRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.web3j.protocol.core.methods.response.Log;

import java.time.Instant;

@Service
@Transactional
public class PoolPriceEventService {

  private final PoolPriceEventRepository poolPriceEventRepository;

  public PoolPriceEventService(PoolPriceEventRepository poolPriceEventRepository) {
    this.poolPriceEventRepository = poolPriceEventRepository;
  }

  public boolean saveIfAbsent(EventLogDecoder.DecodedEvent event, Log log) {
    if (!"SwapPriceLogged".equals(event.eventName())) {
      throw new IllegalArgumentException("only SwapPriceLogged is supported");
    }

    if (poolPriceEventRepository.existsByTxHashAndLogIndex(event.txHash(), event.logIndex())) {
      return false;
    }

    String poolId = log.getTopics().get(1);

    PoolPriceEvent poolPriceEvent = new PoolPriceEvent(
      poolId,
      event.txHash(),
      event.blockNumber(),
      event.logIndex(),
      event.int24(0),
      event.uint160(1),
      Instant.now()
    );

    poolPriceEventRepository.save(poolPriceEvent);
    return true;
  }
}
