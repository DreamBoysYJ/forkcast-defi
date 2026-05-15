package io.forkcast.backend;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(properties = {
  "sync.rpc.url=http://localhost:8545",
  "sync.contracts.strategy-router-address=0x0000000000000000000000000000000000000000",
  "sync.contracts.hook-address=0x0000000000000000000000000000000000000000",
  "STRATEGY_LENS_ADDRESS=0x0000000000000000000000000000000000000000"
})
class BackendApplicationTests {

  @Test
  void contextLoads() {
  }

}
