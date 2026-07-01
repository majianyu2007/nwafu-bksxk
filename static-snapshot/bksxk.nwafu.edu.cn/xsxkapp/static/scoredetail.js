$(function(){
	
	/**
	 * 在线人数提醒
	 */
	;(function (_online) {

	    _online.init = function() {
	        var $tip = $('#noline-tip');
	        setOnlinTip($tip);
	    };

	    function setOnlinTip($tip) {
	        queryOnlineUsers().done(function(resp){
	            var code = resp.code;
	            if(code != null && code == '1') {
	                var data = resp.data;
	                var onlineUsers = data.onlineUsers;
	                $tip.html('（当前选课在线人数 ' + onlineUsers + '人）');
	            }
	        });
	    };

	})(window.CVOnlineTip = window.CVOnlineTip || {});
	
	var self = null;
	
	var viewConfig = {
			
		initialize: function(){
			self = this;
			var studentInfo = JSON.parse(sessionStorage.getItem("studentInfo"));
			$('.scoredetail .xs-detail').html(studentInfo.name + '-' + studentInfo.code);
			var queryParam = {
				electiveBatchCode: studentInfo.electiveBatch.code,
				studentCode: studentInfo.code
			};
			queryXkScore(queryParam).done(function(resp) {
				var code = resp.code;
	            if (code != null && code == '1') {
	            	self.initScoreData(resp.dataList);
	            }else {
	            	$.bhTip({
	                    content: resp.msg,
	                    state: 'danger'
	                });
	            	
	            }
			});
			
		},
		
		initScoreData: function(dataList){
			if(dataList.length > 0){
				var result = [];
				var flag = true;
				$.each(dataList, function(index, obj){
					if(!obj.schoolTermName){
						obj.schoolTermName = '--';
					}
					if(!obj.courseNumber){
						obj.courseNumber = '--';
					}
					if(!obj.courseName){
						obj.courseName = '--';
					}
					if(!obj.score && obj.score !== 0){
						obj.score = '--';
					}
					flag = true;
					$.each(result, function(index1, obj1){
						if(obj.schoolTermName == obj1.schoolTermName){
							obj1.items.push(obj);
							flag = false;
							return false;
						}
					});
					if(flag){
						result.push({
							schoolTermName: obj.schoolTermName,
							items: [obj]
						});
					}
				});
				//排序
				result.sort(function(a, b){
					return a.schoolTermName > b.schoolTermName;
				});
				self.initTable(result);
			}else{
				$('.scoredetail .cj-detail').html('<div style="color: red;">无成绩<div>');
			}
		},
		
		
		initTable: function(result){
			var html = '';
			var htmlTpl = '';
			var tableTpl = '';
			$.each(result, function(index, obj){
				htmlTpl = $('#tpl-score-info').html();
				tableTpl = '';
				$.each(obj.items, function(index1, obj1){
					if(!obj1.courseNumber){
						obj1.courseNumber = '';
					}
					if(!obj1.courseName){
						obj1.courseName = '';
					}
					if(!obj1.credit){
						obj1.credit = '';
					}
					if(!obj1.score){
						obj1.score = '';
					}
					if(!obj1.retakeTypeName){
						obj1.retakeTypeName = '';
					}
					tableTpl += '<tr>' +
									'<td class="kch" title="' + obj1.courseNumber + '"><span>' + obj1.courseNumber + '</span></td>' +
									'<td class="kcm" title="' + obj1.courseName + '"><span>' + obj1.courseName + '</span></td>' +
									'<td class="xf" title="' + obj1.credit + '"><span>' + obj1.credit + '</span></td>' +
									'<td class="cj" title="' + obj1.score + '"><span>' + obj1.score + '</span></td>' +
									'<td class="hdfs" title="' + obj1.retakeTypeName + '"><span>' + obj1.retakeTypeName + '</span></td>' +
								'</tr>';
				});
				htmlTpl = htmlTpl.replace("@schoolTermName", obj.schoolTermName)
								 .replace("@body", tableTpl);
				html += htmlTpl;
			});
			$('.scoredetail .cj-detail').html(html);
		}
		
	};
	
	viewConfig.initialize();
	// 设置页脚固定在页面底部
	xsxkpub.changeCopyRight();
    setContentMinHeight($('.main').children('.cj-container'));
});



