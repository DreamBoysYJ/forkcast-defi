package io.forkcast.backend.chain.service;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

import io.forkcast.backend.chain.domain.RawChainEvent;
import io.forkcast.backend.chain.repository.RawChainEventRepository;
import io.forkcast.backend.chain.client.EventLogDecoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.web3j.protocol.core.methods.response.Log;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
@Transactional
public class RawChainEventService {

  private final RawChainEventRepository rawChainEventRepository;
  private final ObjectMapper objectMapper;

  public RawChainEventService(
    RawChainEventRepository rawChainEventRepository,
    ObjectMapper objectMapper
  ) {
    this.rawChainEventRepository = rawChainEventRepository;
    this.objectMapper = objectMapper;
  }

  public boolean saveIfAbsent(EventLogDecoder.DecodedEvent event, Log log) {
    if (rawChainEventRepository.existsByTxHashAndLogIndex(event.txHash(), event.logIndex())) {
      return false;
    }

    RawChainEvent rawChainEvent = new RawChainEvent(
      event.eventName(),
      event.txHash(),
      event.blockNumber(),
      log.getBlockHash(),
      event.logIndex(),
      event.contractAddress(),
      toPayloadJson(log),
      Instant.now(), // TODO: 나중에 block timestamp로 교체
      log.isRemoved()
    );

    rawChainEventRepository.save(rawChainEvent);
    return true;
  }

  @Transactional(readOnly = true)
  public RawChainEvent getByTxHashAndLogIndexOrThrow(String txHash, int logIndex) {
    return rawChainEventRepository.findByTxHashAndLogIndex(txHash, logIndex)
      .orElseThrow(() -> new IllegalArgumentException(
        "Raw chain event not found: txHash=%s, logIndex=%s".formatted(txHash, logIndex)
      ));
  }

  private String toPayloadJson(Log log) {
    Map<String, Object> payload = new LinkedHashMap<>();
    payload.put("topics", safeTopics(log.getTopics()));
    payload.put("data", log.getData());

    try {
      return objectMapper.writeValueAsString(payload);
    } catch (JacksonException e) {
      throw new IllegalStateException("failed to serialize raw log payload", e);
    }
  }

  private List<String> safeTopics(List<String> topics) {
    return topics == null ? List.of() : topics;
  }
}
