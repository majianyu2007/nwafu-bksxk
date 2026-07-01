/**
 * 
 */
function queryChooseCourse(queryParam) {
	var timestamp=new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/courseResult.do?timestamp=" +  timestamp,
        queryParam == null ? {} : queryParam,
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}

/**
 * 删除志愿选课
 */
function deleteVolunteerResult(deleteParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/deleteVolunteer.do?timestamp=" +  timestamp,
        deleteParam,
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}

/**
 * 订购教材
 */
function bookJxbJcResult(param) {
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/textbook/addbook.do",
			param,
			"post", {}, {
				"token": sessionStorage.token
			}
	);
}
/**
 * 退订教材
 */
function delBookJxbJcResult(param) {
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/textbook/modifybook.do",
			param,
			"post", {}, {
				"token": sessionStorage.token
			}
	);
}

/**
 * 查询名人名言
 */
function queryCelebrityFamous() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/celebrityfamous.do?timestamp=" +  timestamp, {},
        "get"
    );
}


/**
 * 查询教材
 */
function queryJxbJcResult(param) {
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/textbook/queryxsjxbbook.do",
			param,
			"post", {}, {
				"token": sessionStorage.token
			}
	);
}