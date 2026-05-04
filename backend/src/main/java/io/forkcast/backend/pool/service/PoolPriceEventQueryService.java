package io.forkcast.backend.pool.service;


import io.forkcast.backend.pool.dto.PoolPriceEventResponse;
import io.forkcast.backend.pool.repository.PoolPriceEventRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(readOnly = true)
public class PoolPriceEventQueryService {

  private final PoolPriceEventRepository poolPriceEventRepository;

  public PoolPriceEventQueryService(PoolPriceEventRepository poolPriceEventRepository) {
    this.poolPriceEventRepository = poolPriceEventRepository;
  }

  public List<PoolPriceEventResponse> getPriceEvents(String poolId, int limit) {
    return poolPriceEventRepository.findByPoolIdOrderByEventTimestampDesc(poolId, PageRequest.of(0,limit))
      .stream().map(PoolPriceEventResponse::from).toList();
  }
}
