#pragma once

#include <iostream> // fixfix

#include "envoy/http/filter.h"

#include "common/common/assert.h" // fixfix
#include "common/lua/lua.h"

namespace Envoy {
namespace Http {
namespace Filter {
namespace Lua {

/**
 * All stats for the buffer filter. @see stats_macros.h
 */
// clang-format off
/*#define ALL_BUFFER_FILTER_STATS(COUNTER)                                                           \
  COUNTER(rq_timeout)*/
// clang-format on

/**
 * Wrapper struct for buffer filter stats. @see stats_macros.h
 */
/*struct FilterStats {
  ALL_BUFFER_FILTER_STATS(GENERATE_COUNTER_STRUCT)
};*/

/**
 * fixfix
 */
template <class T> class BaseLuaObject {
public:
  typedef std::vector<std::pair<const char*, lua_CFunction>> ExportedFunctions;

  /**
   * fixfix
   */
  template <typename... ConstructorArgs>
  static T* create(lua_State* state, ConstructorArgs&... args) {
    void* mem = lua_newuserdata(state, sizeof(T));
    luaL_getmetatable(state, typeid(T).name());
    lua_setmetatable(state, -2);
    return new (mem) T(args...);
  }

  /**
   * fixfix
   */
  static void registerType(lua_State* state) {
    std::vector<luaL_Reg> to_register;

    // fixfix
    ExportedFunctions functions = T::exportedFunctions();
    for (auto function : functions) {
      to_register.push_back({function.first, function.second});
    }

    // fixfix
    to_register.push_back({"__gc", [](lua_State* state) {
                             static_cast<T*>(luaL_checkudata(state, 1, typeid(T).name()))->~T();
                             return 0;
                           }});

    to_register.push_back({nullptr, nullptr});

    // fixfix
    luaL_newmetatable(state, typeid(T).name());
    lua_pushvalue(state, -1);
    lua_setfield(state, -2, "__index");
    luaL_register(state, nullptr, to_register.data());
  }
};

/**
 * fixfix
 */
class HeaderMapWrapper : public BaseLuaObject<HeaderMapWrapper> {
public:
  HeaderMapWrapper(HeaderMap& headers) : headers_(headers) {}

  static ExportedFunctions exportedFunctions() { return {{"iterate", static_iterate}}; }

private:
  DECLARE_LUA_FUNCTION(HeaderMapWrapper, iterate);

  HeaderMap& headers_;
};

class Filter;

/**
 * fixfix
 */
class RequestHandleWrapper : public BaseLuaObject<RequestHandleWrapper> {
public:
  RequestHandleWrapper(Filter& filter) : filter_(filter) {}

  static ExportedFunctions exportedFunctions() {
    return {{"headers", static_headers},
            {"nextBodyChunk", static_nextBodyChunk},
            {"trailers", static_trailers}};
  }

private:
  DECLARE_LUA_FUNCTION(RequestHandleWrapper, headers);
  DECLARE_LUA_FUNCTION(RequestHandleWrapper, nextBodyChunk);
  DECLARE_LUA_FUNCTION(RequestHandleWrapper, trailers);

  static int bodyIterator(lua_State*) {
    return 0;
  }

  Filter& filter_;
};

/**
 * fixfix
 */
class FilterConfig {
public:
  FilterConfig(const std::string& lua_code) : lua_state_(lua_code) {
    HeaderMapWrapper::registerType(lua_state_.state());
    RequestHandleWrapper::registerType(lua_state_.state());
  }

  Envoy::Lua::ThreadLocalState lua_state_;
};

typedef std::shared_ptr<FilterConfig> FilterConfigConstSharedPtr;

/**
 * fixfix
 */
class Filter : public StreamFilter {
public:
  Filter(FilterConfigConstSharedPtr config) : config_(config) {}
  HeaderMap& requestHeaders() { return *request_headers_; }

  // Http::StreamFilterBase
  void onDestroy() override {}

  // Http::StreamDecoderFilter
  FilterHeadersStatus decodeHeaders(HeaderMap& headers, bool end_stream) override;
  FilterDataStatus decodeData(Buffer::Instance&, bool) override {
    return FilterDataStatus::Continue;
  };
  FilterTrailersStatus decodeTrailers(HeaderMap&) override {
    return FilterTrailersStatus::Continue;
  };
  void setDecoderFilterCallbacks(StreamDecoderFilterCallbacks& callbacks) override {
    decoder_callbacks_ = &callbacks;
  }

  // Http::StreamEncoderFilter
  FilterHeadersStatus encodeHeaders(HeaderMap&, bool) override {
    return FilterHeadersStatus::Continue;
  }
  FilterDataStatus encodeData(Buffer::Instance&, bool) override {
    return FilterDataStatus::Continue;
  };
  FilterTrailersStatus encodeTrailers(HeaderMap&) override {
    return FilterTrailersStatus::Continue;
  };
  void setEncoderFilterCallbacks(StreamEncoderFilterCallbacks& callbacks) override {
    encoder_callbacks_ = &callbacks;
  };

private:
  FilterConfigConstSharedPtr config_;
  StreamDecoderFilterCallbacks* decoder_callbacks_{};
  StreamEncoderFilterCallbacks* encoder_callbacks_{};
  Envoy::Lua::CoroutinePtr on_request_lua_;
  HeaderMap* request_headers_{};
};

} // namespace Lua
} // namespace Filter
} // namespace Http
} // namespace Envoy
