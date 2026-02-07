#include <iostream>
#include "hls_stream.h"
#include "hls_directio.h"

using namespace std;

struct __cosim_T_1__ {char data[1];};
extern "C" void fpga_fifo_push_1(__cosim_T_1__* val, hls::stream<__cosim_T_1__>* fifo) {
  fifo->write(*val);
}
extern "C" void fpga_fifo_pop_1(__cosim_T_1__* val, hls::stream<__cosim_T_1__>* fifo) {
  *val = fifo->read();
}
extern "C" bool fpga_fifo_not_empty_1(hls::stream<__cosim_T_1__>* fifo) {
  return !fifo->empty();
}
extern "C" bool fpga_fifo_exist_1(hls::stream<__cosim_T_1__>* fifo) {
  return fifo->exist();
}
extern "C" bool fpga_direct_valid_1(hls::directio<__cosim_T_1__, 0>* direct) {
  return direct->valid();
}
extern "C" void fpga_direct_load_1(__cosim_T_1__* val, hls::directio<__cosim_T_1__, 0>* direct) {
  *val = direct->read();
}
extern "C" void fpga_direct_store_1(__cosim_T_1__* val, hls::directio<__cosim_T_1__, 0>* direct) {
  direct->write(*val);
}
struct __cosim_T_8__ {char data[8];};
extern "C" void fpga_fifo_push_8(__cosim_T_8__* val, hls::stream<__cosim_T_8__>* fifo) {
  fifo->write(*val);
}
extern "C" void fpga_fifo_pop_8(__cosim_T_8__* val, hls::stream<__cosim_T_8__>* fifo) {
  *val = fifo->read();
}
extern "C" bool fpga_fifo_not_empty_8(hls::stream<__cosim_T_8__>* fifo) {
  return !fifo->empty();
}
extern "C" bool fpga_fifo_exist_8(hls::stream<__cosim_T_8__>* fifo) {
  return fifo->exist();
}
extern "C" bool fpga_direct_valid_8(hls::directio<__cosim_T_8__, 0>* direct) {
  return direct->valid();
}
extern "C" void fpga_direct_load_8(__cosim_T_8__* val, hls::directio<__cosim_T_8__, 0>* direct) {
  *val = direct->read();
}
extern "C" void fpga_direct_store_8(__cosim_T_8__* val, hls::directio<__cosim_T_8__, 0>* direct) {
  direct->write(*val);
}
struct __cosim_T_64__ {char data[64];};
extern "C" void fpga_fifo_push_64(__cosim_T_64__* val, hls::stream<__cosim_T_64__>* fifo) {
  fifo->write(*val);
}
extern "C" void fpga_fifo_pop_64(__cosim_T_64__* val, hls::stream<__cosim_T_64__>* fifo) {
  *val = fifo->read();
}
extern "C" bool fpga_fifo_not_empty_64(hls::stream<__cosim_T_64__>* fifo) {
  return !fifo->empty();
}
extern "C" bool fpga_fifo_exist_64(hls::stream<__cosim_T_64__>* fifo) {
  return fifo->exist();
}
extern "C" bool fpga_direct_valid_64(hls::directio<__cosim_T_64__, 0>* direct) {
  return direct->valid();
}
extern "C" void fpga_direct_load_64(__cosim_T_64__* val, hls::directio<__cosim_T_64__, 0>* direct) {
  *val = direct->read();
}
extern "C" void fpga_direct_store_64(__cosim_T_64__* val, hls::directio<__cosim_T_64__, 0>* direct) {
  direct->write(*val);
}
struct __cosim_T_128__ {char data[128];};
extern "C" void fpga_fifo_push_128(__cosim_T_128__* val, hls::stream<__cosim_T_128__>* fifo) {
  fifo->write(*val);
}
extern "C" void fpga_fifo_pop_128(__cosim_T_128__* val, hls::stream<__cosim_T_128__>* fifo) {
  *val = fifo->read();
}
extern "C" bool fpga_fifo_not_empty_128(hls::stream<__cosim_T_128__>* fifo) {
  return !fifo->empty();
}
extern "C" bool fpga_fifo_exist_128(hls::stream<__cosim_T_128__>* fifo) {
  return fifo->exist();
}
extern "C" bool fpga_direct_valid_128(hls::directio<__cosim_T_128__, 0>* direct) {
  return direct->valid();
}
extern "C" void fpga_direct_load_128(__cosim_T_128__* val, hls::directio<__cosim_T_128__, 0>* direct) {
  *val = direct->read();
}
extern "C" void fpga_direct_store_128(__cosim_T_128__* val, hls::directio<__cosim_T_128__, 0>* direct) {
  direct->write(*val);
}
