#include "common/http/filter/lua/lua_filter.h"

namespace Envoy {
namespace Http {
namespace Filter {
namespace Lua {

int HeaderMapWrapper::iterate(lua_State* state) {
  // fixfix: check function?

  headers_.iterate(
      [](const HeaderEntry& header, void* context) -> void {
        // fixfix
        lua_State* state = static_cast<lua_State*>(context);
        lua_pushvalue(state, -1);
        lua_pushstring(state, header.key().c_str());
        lua_pushstring(state, header.value().c_str());
        lua_pcall(state, 2, 0, 0);
      },
      state);

  return 0;
}

int RequestHandleWrapper::headers(lua_State* state) {
  // fixfix
  HeaderMapWrapper::create(state, filter_.requestHeaders());
  return 1;
}

int RequestHandleWrapper::nextBodyChunk(lua_State* state) {
  // fixfix
  lua_pushcclosure(state, bodyIterator, 1);
  return 1;
}

int RequestHandleWrapper::trailers(lua_State*) {
  // fixfix
  return 0;
}

FilterHeadersStatus Filter::decodeHeaders(HeaderMap& headers, bool) {
  request_headers_ = &headers;

  on_request_lua_ = config_->lua_state_.createCoroutine();
  RequestHandleWrapper::create(on_request_lua_->state(), *this);
  on_request_lua_->start("envoy_on_request", 1);

  return FilterHeadersStatus::Continue;
}

} // namespace Lua
} // namespace Filter
} // namespace Http
} // namespace Envoy
