if (CTFd._internal.challenge) {
  var challenge = CTFd._internal.challenge;
} else {
  var challenge = window.challenge;
}

challenge.data = undefined;

challenge.preRender = function () {};

challenge.render = function () {};

challenge.postRender = function () {
  setTimeout(() => {
    const inputs = document.querySelectorAll(".challenge-desc li");
    let template = `<div class="form-check ctfd-multiple-choice-item" style="padding-left: 0;">
      <label class="cursor-pointer">
        <input type='radio' name='answer' x-model="submission">
        <span></span>
      </label>
    </div>`;

    inputs.forEach((i) => {
      let htmlContent = i.innerHTML;
      let textContent = i.textContent;

      if (htmlContent.startsWith("()") || htmlContent.startsWith("(X)")) {
        const checked = htmlContent.startsWith("(X)") ? "checked" : "";
        let answer = "";

        if (textContent.startsWith("()")) {
          answer = textContent.substring(2).trim();
          htmlContent = htmlContent.substring(2);
        } else if (textContent.startsWith("(X)")) {
          answer = textContent.substring(3).trim();
          htmlContent = htmlContent.substring(3);
        }

        // Create DOM element
        const placeholder = document.createElement("div");
        placeholder.innerHTML = template;
        const node = placeholder.firstElementChild;

        // Manipulate in our answer and checked
        let inputElem = node.querySelector("input");
        inputElem.setAttribute("value", answer);
        node.querySelector("span").innerHTML = htmlContent;
        if (checked) {
          // Make element checked in normal DOM
          inputElem.setAttribute("checked", "checked");
          // Make element checked in Alpine
          inputElem.setAttribute(
            "x-data",
            JSON.stringify({ submission: answer }),
          );
        }

        // Insert into DOM
        i.outerHTML = node.outerHTML;
      }
    });
  }, 200);
};

challenge.submit = async (preview) => {
  const challenge_id = parseInt(document.querySelector("#challenge-id").value);
  const submission = document
    .querySelector(".challenge-desc")
    .querySelector(".ctfd-multiple-choice-item input[type=radio]:checked");

  let value = "";
  if (submission) {
    value = submission.value;
  }

  let res;
  const params = {};
  if (preview) {
    params["preview"] = true;
  }

  res = await CTFd.api.post_challenge_attempt(params, {
    challenge_id: challenge_id,
    submission: value,
  });

  return res;
};
