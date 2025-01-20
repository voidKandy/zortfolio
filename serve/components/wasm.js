request = new XMLHttpRequest();
request.open('GET', 'wasm.wasm');
request.responseType = 'arraybuffer';
request.send();
const memory = new WebAssembly.Memory({ initial: 256, maximum: 512 });


request.onload = function() {
  var bytes = request.response;
  WebAssembly.instantiate(bytes, {
    env: {
      memory,
    }
  })
 .then(result => {
    // do wasm things here!
    var add_two = result.instance.exports.add_two;
    console.log(add_two(3, 5));
  })
  .catch(err => {
    console.error("Failed to initialize WebAssembly module:", err);
  });
};

