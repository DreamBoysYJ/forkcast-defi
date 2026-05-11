package io.forkcast.backend.position.service;

import io.forkcast.backend.position.dto.OpenPositionResponse;
import io.forkcast.backend.position.repository.StrategyPositionRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(readOnly = true)
public class OpenPositionQueryService {

  private final StrategyPositionRepository strategyPositionRepository;

  public OpenPositionQueryService(StrategyPositionRepository strategyPositionRepository) {
    this.strategyPositionRepository = strategyPositionRepository;
  }

  public List<OpenPositionResponse> getOpenPositionsByUser(String userAddress, int limit) {
    return strategyPositionRepository.findByOwnerAddressAndIsOpenTrueOrderByOpenedBlockDesc(userAddress, PageRequest.of(0,limit))
      .stream().map(OpenPositionResponse::from)
      .toList();
  }

  public List<OpenPositionResponse> getOpenPositions(int limit) {
    return strategyPositionRepository.findByIsOpenTrueOrderByOpenedBlockDesc(PageRequest.of(0,limit))
      .stream().map(OpenPositionResponse::from).toList();
  }

  }
