package io.forkcast.backend.chain.client;

import org.springframework.stereotype.Component;
import org.web3j.abi.EventEncoder;
import org.web3j.abi.EventValues;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Event;
import org.web3j.abi.datatypes.Type;
import org.web3j.abi.datatypes.generated.Int24;
import org.web3j.abi.datatypes.generated.Uint160;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.protocol.core.methods.response.Log;
import org.web3j.tx.Contract;

import java.math.BigInteger;
import java.util.List;

@Component
public class EventLogDecoder {

  private static final Event POSITION_OPENED_EVENT = new Event(
    "PositionOpened",
    List.of(
      new TypeReference<Address>(true) {},
      new TypeReference<Address>(true) {},
      new TypeReference<Address>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Address>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {}
    )
  );

  private static final Event POSITION_CLOSED_EVENT = new Event(
    "PositionClosed",
    List.of(
      new TypeReference<Address>(true) {},
      new TypeReference<Address>(true) {},
      new TypeReference<Uint256>(true) {},
      new TypeReference<Address>() {},
      new TypeReference<Address>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {}
    )
  );

  private static final Event FEES_COLLECTED_EVENT = new Event(
    "FeesCollected",
    List.of(
      new TypeReference<Address>(true) {},
      new TypeReference<Uint256>(true) {},
      new TypeReference<Address>() {},
      new TypeReference<Address>() {},
      new TypeReference<Uint256>() {},
      new TypeReference<Uint256>() {}
    )
  );

  private static final Event SWAP_PRICE_LOGGED_EVENT = new Event(
    "SwapPriceLogged",
    List.of(
      new TypeReference<org.web3j.abi.datatypes.generated.Bytes32>(true) {},
      new TypeReference<Int24>() {},
      new TypeReference<Uint160>() {},
      new TypeReference<Uint256>() {}
    )
  );

  private static final String POSITION_OPENED_TOPIC = EventEncoder.encode(POSITION_OPENED_EVENT);
  private static final String POSITION_CLOSED_TOPIC = EventEncoder.encode(POSITION_CLOSED_EVENT);
  private static final String FEES_COLLECTED_TOPIC = EventEncoder.encode(FEES_COLLECTED_EVENT);
  private static final String SWAP_PRICE_LOGGED_TOPIC = EventEncoder.encode(SWAP_PRICE_LOGGED_EVENT);

  public DecodedEvent decode(Log log) {
    String topic0 = log.getTopics().get(0);

    if (POSITION_OPENED_TOPIC.equalsIgnoreCase(topic0)) {
      return decodePositionOpened(log);
    }

    if (POSITION_CLOSED_TOPIC.equalsIgnoreCase(topic0)) {
      return decodePositionClosed(log);
    }

    if (FEES_COLLECTED_TOPIC.equalsIgnoreCase(topic0)) {
      return decodeFeesCollected(log);
    }

    if (SWAP_PRICE_LOGGED_TOPIC.equalsIgnoreCase(topic0)) {
      return decodeSwapPriceLogged(log);
    }

    throw new IllegalArgumentException("unsupported topic0: " + topic0);
  }

  private DecodedEvent decodePositionOpened(Log log) {
    EventValues values = requireValues(
      Contract.staticExtractEventParameters(POSITION_OPENED_EVENT, log),
      "PositionOpened"
    );

    List<Type> indexed = values.getIndexedValues();
    List<Type> nonIndexed = values.getNonIndexedValues();

    return new DecodedEvent(
      "PositionOpened",
      log.getTransactionHash(),
      log.getBlockNumber().longValue(),
      log.getLogIndex().intValue(),
      log.getAddress(),
      indexed.get(0).getValue().toString(),
      indexed.get(1).getValue().toString(),
      indexed,
      nonIndexed
    );
  }

  private DecodedEvent decodePositionClosed(Log log) {
    EventValues values = requireValues(
      Contract.staticExtractEventParameters(POSITION_CLOSED_EVENT, log),
      "PositionClosed"
    );

    List<Type> indexed = values.getIndexedValues();
    List<Type> nonIndexed = values.getNonIndexedValues();

    return new DecodedEvent(
      "PositionClosed",
      log.getTransactionHash(),
      log.getBlockNumber().longValue(),
      log.getLogIndex().intValue(),
      log.getAddress(),
      indexed.get(0).getValue().toString(),
      indexed.get(1).getValue().toString(),
      indexed,
      nonIndexed
    );
  }

  private DecodedEvent decodeFeesCollected(Log log) {
    EventValues values = requireValues(
      Contract.staticExtractEventParameters(FEES_COLLECTED_EVENT, log),
      "FeesCollected"
    );

    List<Type> indexed = values.getIndexedValues();
    List<Type> nonIndexed = values.getNonIndexedValues();

    return new DecodedEvent(
      "FeesCollected",
      log.getTransactionHash(),
      log.getBlockNumber().longValue(),
      log.getLogIndex().intValue(),
      log.getAddress(),
      indexed.get(0).getValue().toString(),
      null,
      indexed,
      nonIndexed
    );
  }

  private DecodedEvent decodeSwapPriceLogged(Log log) {
    EventValues values = requireValues(
      Contract.staticExtractEventParameters(SWAP_PRICE_LOGGED_EVENT, log),
      "SwapPriceLogged"
    );

    List<Type> indexed = values.getIndexedValues();
    List<Type> nonIndexed = values.getNonIndexedValues();

    return new DecodedEvent(
      "SwapPriceLogged",
      log.getTransactionHash(),
      log.getBlockNumber().longValue(),
      log.getLogIndex().intValue(),
      log.getAddress(),
      null,
      null,
      indexed,
      nonIndexed
    );
  }

  private EventValues requireValues(EventValues values, String eventName) {
    if (values == null) {
      throw new IllegalArgumentException("failed to decode " + eventName);
    }
    return values;
  }

  public record DecodedEvent(
    String eventName,
    String txHash,
    long blockNumber,
    int logIndex,
    String contractAddress,
    String userAddress,
    String vaultAddress,
    List<Type> indexedValues,
    List<Type> values
  ) {
    public BigInteger uint256(int index) {
      return (BigInteger) values.get(index).getValue();
    }

    public String address(int index) {
      return values.get(index).getValue().toString();
    }

    public int int24(int index) {
      return ((BigInteger) values.get(index).getValue()).intValue();
    }

    public BigInteger uint160(int index) {
      return (BigInteger) values.get(index).getValue();
    }

    public BigInteger indexedUint256(int index) {
      return (BigInteger) indexedValues.get(index).getValue();
    }

    public String indexedAddress(int index) {
      return indexedValues.get(index).getValue().toString();
    }
  }
}
