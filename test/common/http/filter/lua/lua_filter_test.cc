#include "common/http/filter/lua/lua_filter.h"

#include "test/test_common/utility.h"

#include "gmock/gmock.h"

namespace Envoy {
namespace Http {
namespace Filter {
namespace Lua {

class LuaHttpFilterTest : public testing::Test {
public:
  void setup(const std::string& lua_code) {
    config_.reset(new FilterConfig(lua_code));
    filter_.reset(new Filter(config_));
  }

  std::shared_ptr<FilterConfig> config_;
  std::unique_ptr<Filter> filter_;
};

TEST_F(LuaHttpFilterTest, FixFix) {
  const std::string code(R"EOF(
    function envoy_on_request(request_handle)
      print(request_handle)

      headers = request_handle:headers()
      print(headers)

      headers:iterate(
        function(key, value)
          print(string.format("'%s' '%s'", key, value))
        end
      )

      for chunk in request_handle:nextBodyChunk() do
        print(chunk)
      end
    end
  )EOF");

  setup(code);

  TestHeaderMapImpl request_headers{{":path", "/"}};
  filter_->decodeHeaders(request_headers, true);
}

} // namespace Lua
} // namespace Filter
} // namespace Http
} // namespace Envoy
